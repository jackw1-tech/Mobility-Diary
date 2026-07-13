"""Adapter del modello HAR CNN+GRU.

Il worker passa qui finestre raw 500x6 (accelerometro+giroscopio), estrae
embedding con CNN 1D e predice sequenze da 32 finestre con GRU.
"""

from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np
from django.conf import settings

from ..models import ActivityLabel

MODEL_CLASS_NAMES = ("IDLE", "WALKING", "RUNNING", "BIKING", "DRIVING")
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


_MODEL_BUNDLE: HarModelBundle | None = None


def reset_model_cache() -> None:
    global _MODEL_BUNDLE
    _MODEL_BUNDLE = None

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


def predict_window_label(
    matrix,
) -> tuple[str, float]:
    model_bundle = _load_model_bundle()
    x = np.expand_dims(_prepare_har_window_matrix(matrix), axis=0)
    probs = np.asarray(_predict(model_bundle.classifier, x), dtype=np.float32)
    if probs.shape != (1, len(MODEL_CLASS_NAMES)):
        raise ValueError(
            f"CNN HAR ha prodotto probabilita con shape inattesa: {probs.shape}"
        )
    idx = int(np.argmax(probs[0]))
    return MODEL_TO_ACTIVITY_LABEL[MODEL_CLASS_NAMES[idx]].value, float(probs[0][idx])

""" 
Prende la lista delle sensor window e le da all HAR
"""
def predict_activity_windows(
    windows,
) -> HarPredictionResult:
    if not windows:
        return HarPredictionResult(
            labels=[],
            confidences=[],
            summary={
                "classifier": "keras_cnn_gru",
                "window_count": 0,
                "label_distribution": {},
                "confidence": _confidence_summary([]),
            },
        )

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
    labels = [MODEL_TO_ACTIVITY_LABEL[name].value for name in model_classes]
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
