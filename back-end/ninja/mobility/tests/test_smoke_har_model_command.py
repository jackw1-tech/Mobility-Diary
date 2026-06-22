from types import SimpleNamespace

import pytest
from django.core.management import call_command
from django.core.management.base import CommandError

from mobility.ml.har_adapter import HarModelUnavailable, HarPredictionResult


def test_smoke_har_model_command_reports_prediction(monkeypatch, capsys):
    seen = {}

    def fake_predict(windows):
        seen["window_count"] = len(windows)
        seen["shape"] = windows[0].matrix.shape
        return HarPredictionResult(
            labels=["IDLE"],
            confidences=[0.99],
            summary={
                "label_distribution": {"IDLE": 1},
                "confidence": {"mean": 0.99, "min": 0.99, "max": 0.99},
            },
        )

    monkeypatch.setattr(
        "mobility.management.commands.smoke_har_model.predict_activity_windows",
        fake_predict,
    )

    call_command("smoke_har_model")

    assert seen == {"window_count": 1, "shape": (500, 9)}
    output = capsys.readouterr().out
    assert "HAR model smoke test OK" in output
    assert "labels: {'IDLE': 1}" in output


def test_smoke_har_model_command_fails_when_model_is_unavailable(monkeypatch):
    def fake_predict(_windows):
        raise HarModelUnavailable("modello CNN HAR non trovato")

    monkeypatch.setattr(
        "mobility.management.commands.smoke_har_model.predict_activity_windows",
        fake_predict,
    )

    with pytest.raises(CommandError, match="modello CNN HAR non trovato"):
        call_command("smoke_har_model")


def test_smoke_har_model_command_rejects_invalid_window_count():
    with pytest.raises(CommandError, match="almeno 1"):
        call_command("smoke_har_model", windows=0)
