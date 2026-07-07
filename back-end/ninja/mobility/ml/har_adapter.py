"""Adapter del modello HAR CNN+GRU.

Il worker passa qui finestre raw 500x6 (accelerometro+giroscopio), estrae
embedding con CNN 1D e predice sequenze da 32 finestre con GRU.
"""

from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

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


class PredictableModel(Protocol):
    def predict(self, data, *args, **kwargs): ...


@dataclass(frozen=True)
class HarPredictionResult:
    labels: list[str]
    confidences: list[float]
    summary: dict


@dataclass(frozen=True)
class HarModelBundle:
    extractor: PredictableModel
    gru: PredictableModel
    sequence_length: int
    cnn_model_path: str
    gru_model_path: str
    # CNN completo con testa softmax: classifica una singola finestra senza GRU.
    classifier: PredictableModel | None = None


_MODEL_BUNDLE: HarModelBundle | None = None


def reset_model_cache() -> None:
    global _MODEL_BUNDLE
    _MODEL_BUNDLE = None


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


def _predict(model: PredictableModel, data):
    try:
        return model.predict(data, verbose=0)
    except TypeError:
        return model.predict(data)


def _project_window_matrix(matrix) -> np.ndarray:
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
    *,
    bundle: HarModelBundle | None = None,
) -> tuple[str, float]:
    """Classifica una singola finestra 500x6 col solo CNN, senza contesto GRU.

    Restituisce (ActivityLabel.value, confidenza). Usato dalla classificazione
    live dell'assistente di percorso, dove esiste solo il presente.
    """
    model_bundle = bundle or _load_model_bundle()
    x = np.expand_dims(_project_window_matrix(matrix), axis=0)
    probs = np.asarray(_predict(model_bundle.classifier, x), dtype=np.float32)
    if probs.shape != (1, len(MODEL_CLASS_NAMES)):
        raise ValueError(
            f"CNN HAR ha prodotto probabilita con shape inattesa: {probs.shape}"
        )
    idx = int(np.argmax(probs[0]))
    return MODEL_TO_ACTIVITY_LABEL[MODEL_CLASS_NAMES[idx]].value, float(probs[0][idx])


def predict_activity_windows(
    windows,
    *,
    bundle: HarModelBundle | None = None,
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

    model_bundle = bundle or _load_model_bundle()
    x_raw = np.stack([_project_window_matrix(window.matrix) for window in windows])

    embeddings = np.asarray(_predict(model_bundle.extractor, x_raw), dtype=np.float32)
    if embeddings.ndim != 2 or embeddings.shape[0] != len(windows):
        raise ValueError(
            "estrattore CNN HAR ha prodotto embedding con shape inattesa: "
            f"{embeddings.shape}"
        )

    sequence_length = model_bundle.sequence_length

    sequence_segments = []
    sequence_lengths = []
    for start in range(0, len(windows), sequence_length):
        segment = embeddings[start : start + sequence_length]
        current_length = len(segment)
        sequence_lengths.append(current_length)
        if current_length < sequence_length:
            padding = np.zeros(
                (sequence_length - current_length, embeddings.shape[1]),
                dtype=embeddings.dtype,
            )
            segment = np.concatenate([segment, padding])
        sequence_segments.append(segment)

    batched_segments = np.stack(sequence_segments)
    prediction = np.asarray(
        _predict(model_bundle.gru, batched_segments),
        dtype=np.float32,
    )
    if prediction.shape != (
        len(sequence_segments),
        sequence_length,
        len(MODEL_CLASS_NAMES),
    ):
        raise ValueError(
            "modello GRU HAR ha prodotto probabilita con shape inattesa: "
            f"{prediction.shape}"
        )

    labels_idx = np.zeros(len(windows), dtype=int)
    all_probs = np.zeros((len(windows), len(MODEL_CLASS_NAMES)), dtype=np.float32)
    output_start = 0
    for sequence_index, current_length in enumerate(sequence_lengths):
        valid = prediction[sequence_index, :current_length]
        labels_idx[output_start : output_start + current_length] = np.argmax(
            valid,
            axis=1,
        )
        all_probs[output_start : output_start + current_length] = valid
        output_start += current_length

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
