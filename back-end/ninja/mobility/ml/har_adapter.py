"""Adapter unico per il modello HAR fused CNN+GRU."""

from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np
from django.conf import settings

from ..models import ActivityLabel


class HarModelUnavailable(RuntimeError):
    """Il modello non puo essere caricato nel runtime corrente."""


@dataclass(frozen=True)
class HarPredictionResult:
    labels: list[str]
    confidences: list[float]
    diagnostics: dict


@dataclass(frozen=True)
class HarModelBundle:
    classifier: Any
    sequence_length: int
    model_path: str
    inference_path: str


_MODEL_BUNDLE: HarModelBundle | None = None


def reset_model_cache() -> None:
    global _MODEL_BUNDLE
    _MODEL_BUNDLE = None


def warm_har_model() -> None:
    _load_model_bundle()


def _load_inference_class():
    try:
        from manual_har.inference import HARClassifier
    except ModuleNotFoundError as exc:
        raise HarModelUnavailable(
            f"modulo inferenza HAR fused non disponibile: {exc}"
        ) from exc
    return HARClassifier


#Caricamento / Creazione del modello
def _load_model_bundle() -> HarModelBundle:
    global _MODEL_BUNDLE
    if _MODEL_BUNDLE is not None:
        return _MODEL_BUNDLE

    model_path = Path(settings.HAR_FUSED_MODEL_PATH)
    if not model_path.exists():
        raise HarModelUnavailable(f"modello HAR fused non trovato: {model_path}")

    try:
        classifier_class = _load_inference_class()
        classifier = classifier_class(
            str(model_path),
            seq_len=settings.HAR_FUSED_SEQUENCE_LENGTH,
        )
    except ModuleNotFoundError as exc:
        raise HarModelUnavailable(
            "tensorflow non installato nel runtime del worker"
        ) from exc

    _MODEL_BUNDLE = HarModelBundle(
        classifier=classifier,
        sequence_length=settings.HAR_FUSED_SEQUENCE_LENGTH,
        model_path=str(model_path),
        inference_path=str(settings.HAR_FUSED_INFERENCE_PATH),
    )
    return _MODEL_BUNDLE


#Prende la matrice grezza 500 x 6 , la pulisca e la prepara nel modo che vuole il modlelo
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


def _confidence_metrics(confidences: list[float]) -> dict:
    if not confidences:
        return {"mean": None, "min": None, "max": None}
    return {
        "mean": float(np.mean(confidences)),
        "min": float(np.min(confidences)),
        "max": float(np.max(confidences)),
    }


# Chiama l'har davvero
def _predict(model_bundle: HarModelBundle, matrices: np.ndarray) -> tuple[list[str], list[float], list[str]]:
    prediction = model_bundle.classifier.predict(matrices)
    probs = np.asarray(prediction["probs"], dtype=np.float32)
    label_indices = np.asarray(prediction["labels"])
    classes = [str(c) for c in prediction["classes"]]

    for c in classes:
        if c not in ActivityLabel.values:
            raise ValueError(f"modello HAR con classi non supportate: {c}")

    expected_shape = (len(matrices), len(classes))
    if probs.shape != expected_shape or label_indices.shape != (len(matrices),):
        raise ValueError(
            f"modello HAR ha prodotto output con shape inattesa: "
            f"probs={probs.shape}, labels={label_indices.shape}"
        )
    #Traduciamo numeri modello har -> label di movimento
    labels = [classes[int(index)] for index in label_indices]
    confidences = [float(prob.max()) for prob in probs]
    return labels, confidences, classes

#Predizione singola in modalità live della 500 x 6
def predict_window_label(matrix) -> tuple[str, float]:
    matrices = np.expand_dims(_prepare_har_window_matrix(matrix), axis=0) #Aggiunge 1 dimensione (1,500,6)
    labels, confidences, _classes = _predict(_load_model_bundle(), matrices)
    return labels[0], confidences[0]


#Wrapper che poi chiama davvero l har
def predict_activity_windows(windows) -> HarPredictionResult:
    if not windows:
        return HarPredictionResult(
            labels=[],
            confidences=[],
            diagnostics={
                "classifier": "keras_fused_cnn_gru",
                "window_count": 0,
                "label_distribution": {},
                "confidence": _confidence_metrics([]),
            },
        )

    matrices = np.stack(
        [_prepare_har_window_matrix(window.matrix) for window in windows]
    )
    model_bundle = _load_model_bundle()
    labels, confidences, classes = _predict(model_bundle, matrices)
    return HarPredictionResult(
        labels=labels,
        confidences=confidences,
        diagnostics={
            "classifier": "keras_fused_cnn_gru",
            "model_classes": classes,
            "fused_model": Path(model_bundle.model_path).name,
            "sequence_length": model_bundle.sequence_length,
            "window_count": len(windows),
            "label_distribution": dict(Counter(labels)),
            "confidence": _confidence_metrics(confidences),
        },
    )
