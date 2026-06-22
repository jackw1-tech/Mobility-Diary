from types import SimpleNamespace

import numpy as np
import pytest

from mobility.ml import classifier
from mobility.ml.har_adapter import (
    HarModelBundle,
    HarModelUnavailable,
    _project_window_matrix,
    predict_activity_windows,
)


class FakeExtractor:
    def __init__(self):
        self.seen = None

    def predict(self, data, **kwargs):
        self.seen = data
        return np.ones((data.shape[0], 4), dtype=np.float32)


class FakeGru:
    def __init__(self):
        self.seen = None

    def predict(self, data, **kwargs):
        self.seen = data
        probabilities = np.zeros((1, 32, 5), dtype=np.float32)
        probabilities[0, :, 0] = 0.25
        probabilities[0, 0, 4] = 0.9
        probabilities[0, 1, 1] = 0.8
        return probabilities


def _matrix(samples: int = 500, channels: int = 9):
    row = [float(i) for i in range(channels)]
    return [row for _ in range(samples)]


def test_predict_activity_windows_projects_to_six_channels_and_maps_driving():
    extractor = FakeExtractor()
    gru = FakeGru()
    bundle = HarModelBundle(
        extractor=extractor,
        gru=gru,
        sequence_length=32,
        cnn_model_path="/models/cnn.keras",
        gru_model_path="/models/gru.keras",
    )
    windows = [
        SimpleNamespace(matrix=_matrix()),
        SimpleNamespace(matrix=_matrix()),
    ]

    result = predict_activity_windows(windows, bundle=bundle)

    assert extractor.seen.shape == (2, 500, 6)
    assert extractor.seen[0, 0].tolist() == [0, 1, 2, 3, 4, 5]
    assert gru.seen.shape == (1, 32, 4)
    assert result.labels == ["MOVING_VEHICLE", "WALKING"]
    assert result.confidences == pytest.approx([0.9, 0.8])
    assert result.summary["classifier"] == "keras_cnn_gru"
    assert result.summary["label_distribution"] == {
        "MOVING_VEHICLE": 1,
        "WALKING": 1,
    }


def test_project_window_matrix_rejects_invalid_shape():
    with pytest.raises(ValueError, match="499 campioni"):
        _project_window_matrix(_matrix(samples=499))

    with pytest.raises(ValueError, match="meno di 6 canali"):
        _project_window_matrix(_matrix(channels=5))


def test_classifier_falls_back_to_speed_when_model_is_unavailable(settings, monkeypatch):
    settings.HAR_MODEL_REQUIRED = False

    def unavailable(_windows):
        raise HarModelUnavailable("artifact mancanti")

    monkeypatch.setattr(classifier, "predict_activity_windows", unavailable)

    result = classifier.classify_windows(
        [],
        [0.0, 4.2],
        raw_windows=[object(), object()],
    )

    assert result.labels == ["IDLE", "BIKING"]
    assert result.summary == {
        "classifier": "placeholder_gps_speed",
        "fallback_reason": "artifact mancanti",
    }
