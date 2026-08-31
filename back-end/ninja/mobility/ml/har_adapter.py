"""Adapter del modello HAR CNN+GRU.

Il worker passa qui finestre raw 500x6 (accelerometro+giroscopio), estrae
embedding con CNN 1D e predice sequenze da 32 finestre con GRU.
"""

from __future__ import annotations

import logging
from collections import Counter
from dataclasses import dataclass
import importlib.util
from pathlib import Path
from time import perf_counter
from typing import Any

import numpy as np
import requests
from django.conf import settings

from ..models import ActivityLabel

logger = logging.getLogger(__name__)

MODEL_CLASS_NAMES = ("IDLE", "WALKING", "RUNNING", "BIKING", "DRIVING")
FUSED_MODEL_CLASS_NAMES = ("IDLE", "WALKING", "RUNNING", "BIKING", "MOVING_VEHICLE")
MODEL_TO_ACTIVITY_LABEL = {
    "IDLE": ActivityLabel.IDLE,
    "WALKING": ActivityLabel.WALKING,
    "RUNNING": ActivityLabel.RUNNING,
    "BIKING": ActivityLabel.BIKING,
    "DRIVING": ActivityLabel.MOVING_VEHICLE,
}


class HarModelUnavailable(RuntimeError):
    """Il modello non puo essere caricato nel runtime corrente."""


@dataclass(frozen=True)
class HarPredictionResult:
    labels: list[str]
    confidences: list[float]
    summary: dict


@dataclass(frozen=True)
class HarModelBundle:
    extractor: Any
    gru: Any
    sequence_length: int
    cnn_model_path: str
    gru_model_path: str
    classifier: Any = None


@dataclass(frozen=True)
class FusedHarModelBundle:
    classifier: Any
    sequence_length: int
    model_path: str
    inference_path: str


_MODEL_BUNDLE: HarModelBundle | None = None
_FUSED_MODEL_BUNDLE: FusedHarModelBundle | None = None


def reset_model_cache() -> None:
    global _MODEL_BUNDLE, _FUSED_MODEL_BUNDLE
    _MODEL_BUNDLE = None
    _FUSED_MODEL_BUNDLE = None


def warm_har_model() -> None:
    if _should_use_fused_model():
        _load_fused_model_bundle()
        return
    _load_model_bundle()


def _should_use_fused_model() -> bool:
    backend = settings.HAR_MODEL_BACKEND.lower()
    if backend == "fused":
        return True
    if backend == "legacy":
        return False
    return Path(settings.HAR_FUSED_MODEL_PATH).exists()


def _load_fused_inference_class():
    inference_path = Path(settings.HAR_FUSED_INFERENCE_PATH)
    if not inference_path.exists():
        raise HarModelUnavailable(
            f"modulo inferenza HAR fused non trovato: {inference_path}"
        )
    spec = importlib.util.spec_from_file_location(
        "manual_har_fused_inference",
        inference_path,
    )
    if spec is None or spec.loader is None:
        raise HarModelUnavailable(
            f"modulo inferenza HAR fused non caricabile: {inference_path}"
        )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.HARClassifier


def _load_fused_model_bundle() -> FusedHarModelBundle:
    global _FUSED_MODEL_BUNDLE
    if _FUSED_MODEL_BUNDLE is not None:
        return _FUSED_MODEL_BUNDLE

    model_path = Path(settings.HAR_FUSED_MODEL_PATH)
    if not model_path.exists():
        raise HarModelUnavailable(f"modello HAR fused non trovato: {model_path}")

    try:
        classifier_class = _load_fused_inference_class()
        classifier = classifier_class(
            str(model_path),
            seq_len=settings.HAR_FUSED_SEQUENCE_LENGTH,
        )
    except ModuleNotFoundError as exc:
        raise HarModelUnavailable(
            "tensorflow non installato nel runtime del worker"
        ) from exc

    _FUSED_MODEL_BUNDLE = FusedHarModelBundle(
        classifier=classifier,
        sequence_length=settings.HAR_FUSED_SEQUENCE_LENGTH,
        model_path=str(model_path),
        inference_path=str(settings.HAR_FUSED_INFERENCE_PATH),
    )
    return _FUSED_MODEL_BUNDLE

""" 
Carica i modelli Har e li mette in cache
"""
def _load_model_bundle() -> HarModelBundle:
    global _MODEL_BUNDLE
    if _MODEL_BUNDLE is not None:
        return _MODEL_BUNDLE

    cnn_path = Path(settings.HAR_CNN_MODEL_PATH)
    gru_path = Path(settings.HAR_GRU_MODEL_PATH)
    if not cnn_path.exists():
        raise HarModelUnavailable(f"modello CNN HAR non trovato: {cnn_path}")
    if not gru_path.exists():
        raise HarModelUnavailable(f"modello GRU HAR non trovato: {gru_path}")

    try:
        import tensorflow as tf
        from tensorflow.keras.models import Model
    except ModuleNotFoundError as exc:
        raise HarModelUnavailable(
            "tensorflow non installato nel runtime del worker"
        ) from exc

    cnn = tf.keras.models.load_model(cnn_path, compile=False)
    extractor = Model(cnn.inputs, cnn.layers[-3].output)
    gru = tf.keras.models.load_model(gru_path, compile=False)
    _MODEL_BUNDLE = HarModelBundle(
        extractor=extractor,
        gru=gru,
        sequence_length=settings.HAR_GRU_SEQUENCE_LENGTH,
        cnn_model_path=str(cnn_path),
        gru_model_path=str(gru_path),
        classifier=cnn,
    )
    return _MODEL_BUNDLE


def _predict(model: Any, data):
    try:
        return model.predict(data, verbose=0)
    except TypeError:
        return model.predict(data)

""" 
Converte tutti i numeri in float 32
"""
def _prepare_har_window_matrix(matrix) -> np.ndarray:
    arr = np.asarray(matrix, dtype=np.float32)
    expected_samples = settings.HAR_WINDOW_SAMPLE_COUNT
    if arr.ndim != 2:
        raise ValueError("finestra HAR con matrice non bidimensionale")
    if arr.shape[0] != expected_samples:
        raise ValueError(
            f"finestra HAR con {arr.shape[0]} campioni, attesi {expected_samples}"
        )
    if arr.shape[1] < 6:
        raise ValueError("finestra HAR con meno di 6 canali")
    return arr[:, :6]


def _confidence_summary(confidences: list[float]) -> dict:
    if not confidences:
        return {"mean": None, "min": None, "max": None}
    return {
        "mean": float(np.mean(confidences)),
        "min": float(np.min(confidences)),
        "max": float(np.max(confidences)),
    }


def _activity_label_value(model_class_name: str) -> str:
    label = MODEL_TO_ACTIVITY_LABEL.get(model_class_name, model_class_name)
    return label.value if hasattr(label, "value") else str(label)


def predict_window_label(
    matrix,
) -> tuple[str, float]:
    """Classifica una singola finestra 500x6: prova prima il servizio HAR
    remoto (se configurato), ricade sul modello locale se non risponde in
    tempo o fallisce."""
    remote_result = _predict_window_label_remote(matrix)
    if remote_result is not None:
        return remote_result
    return _predict_window_label_local(matrix)


def _predict_window_label_remote(matrix) -> tuple[str, float] | None:
    url = settings.MODAL_HAR_CLASSIFY_URL
    if not url:
        return None
    started = perf_counter()
    try:
        response = requests.post(
            url,
            json={"samples": matrix},
            timeout=settings.MODAL_HAR_CLASSIFY_TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        payload = response.json()
        label = str(payload["label"])
        confidence = float(payload["confidence"])
    except (requests.RequestException, KeyError, TypeError, ValueError) as exc:
        logger.warning(
            "Inferenza HAR remota fallita dopo %.2f ms, fallback locale: %s",
            (perf_counter() - started) * 1000,
            exc,
        )
        return None
    logger.info(
        "Inferenza HAR remota completata in %.2f ms",
        (perf_counter() - started) * 1000,
    )
    return label, confidence


def _predict_window_label_local(matrix) -> tuple[str, float]:
    started = perf_counter()
    try:
        if _should_use_fused_model():
            model_bundle = _load_fused_model_bundle()
            x = np.expand_dims(_prepare_har_window_matrix(matrix), axis=0)
            prediction = model_bundle.classifier.predict(x)
            probs = np.asarray(prediction["probs"], dtype=np.float32)
            idx = int(np.argmax(probs[0]))
            label = prediction["classes"][idx]
            return _activity_label_value(label), float(probs[0][idx])

        model_bundle = _load_model_bundle()
        x = np.expand_dims(_prepare_har_window_matrix(matrix), axis=0)
        probs = np.asarray(_predict(model_bundle.classifier, x), dtype=np.float32)
        if probs.shape != (1, len(MODEL_CLASS_NAMES)):
            raise ValueError(
                f"CNN HAR ha prodotto probabilita con shape inattesa: {probs.shape}"
            )
        idx = int(np.argmax(probs[0]))
        return _activity_label_value(MODEL_CLASS_NAMES[idx]), float(probs[0][idx])
    finally:
        logger.info(
            "Inferenza HAR (singola finestra, locale) completata in %.2f ms",
            (perf_counter() - started) * 1000,
        )

""" 
Prende la lista delle sensor window e le da all HAR
"""
def predict_activity_windows(
    windows,
) -> HarPredictionResult:
    if not windows:
        classifier_name = (
            "keras_fused_cnn_gru"
            if _should_use_fused_model()
            else "keras_cnn_gru"
        )
        return HarPredictionResult(
            labels=[],
            confidences=[],
            summary={
                "classifier": classifier_name,
                "window_count": 0,
                "label_distribution": {},
                "confidence": _confidence_summary([]),
            },
        )

    if _should_use_fused_model():
        return _predict_activity_windows_fused(windows)

    model_bundle = _load_model_bundle()
    x_raw = np.stack([_prepare_har_window_matrix(window.matrix) for window in windows])
    # -> ( len(windows), 500 , 6  )

    embeddings = np.asarray(_predict(model_bundle.extractor, x_raw), dtype=np.float32)
    # -> ( len(windows), embedding_dim )

    sequence_length = model_bundle.sequence_length
    sequence_count = int(np.ceil(len(windows) / sequence_length))
    padded_length = sequence_count * sequence_length
    padded_embeddings = np.zeros(
        (padded_length, embeddings.shape[1]),
        dtype=embeddings.dtype,
    )
    padded_embeddings[: len(windows)] = embeddings
    gru_input = padded_embeddings.reshape(
        (sequence_count, sequence_length, embeddings.shape[1])
    )

    predictions = np.asarray(_predict(model_bundle.gru, gru_input), dtype=np.float32)
    all_probs = predictions.reshape(
        (padded_length, len(MODEL_CLASS_NAMES))
    )[: len(windows)]
    labels_idx = np.argmax(all_probs, axis=1)

    model_classes = [MODEL_CLASS_NAMES[idx] for idx in labels_idx]
    labels = [_activity_label_value(name) for name in model_classes]
    confidences = [float(prob.max()) for prob in all_probs]
    distribution = dict(Counter(labels))

    return HarPredictionResult(
        labels=labels,
        confidences=confidences,
        summary={
            "classifier": "keras_cnn_gru",
            "model_classes": list(MODEL_CLASS_NAMES),
            "cnn_model": Path(model_bundle.cnn_model_path).name,
            "gru_model": Path(model_bundle.gru_model_path).name,
            "sequence_length": sequence_length,
            "window_count": len(windows),
            "label_distribution": distribution,
            "confidence": _confidence_summary(confidences),
        },
    )


def _predict_activity_windows_fused(windows) -> HarPredictionResult:
    model_bundle = _load_fused_model_bundle()
    x_raw = np.stack([_prepare_har_window_matrix(window.matrix) for window in windows])
    prediction = model_bundle.classifier.predict(x_raw)
    probs = np.asarray(prediction["probs"], dtype=np.float32)
    labels_idx = np.asarray(prediction["labels"])
    classes = list(prediction.get("classes", FUSED_MODEL_CLASS_NAMES))
    model_classes = [classes[int(idx)] for idx in labels_idx]
    labels = [_activity_label_value(name) for name in model_classes]
    confidences = [float(prob.max()) for prob in probs]
    distribution = dict(Counter(labels))

    return HarPredictionResult(
        labels=labels,
        confidences=confidences,
        summary={
            "classifier": "keras_fused_cnn_gru",
            "model_classes": classes,
            "fused_model": Path(model_bundle.model_path).name,
            "sequence_length": model_bundle.sequence_length,
            "window_count": len(windows),
            "label_distribution": distribution,
            "confidence": _confidence_summary(confidences),
        },
    )
