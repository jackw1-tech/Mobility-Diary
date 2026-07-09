import pytest

from mobility.services import route_assistant
from mobility.services.route_assistant import (
    RouteAssistantValidationError,
    classify_route_assistant_samples,
)


def _samples(count: int) -> list[list[float]]:
    return [[0.0, 0.0, 9.8, 0.1, 0.2, 0.3] for _ in range(count)]


def test_route_assistant_rejects_invalid_window(settings):
    settings.HAR_WINDOW_SAMPLE_COUNT = 2

    with pytest.raises(RouteAssistantValidationError, match="finestra sensori"):
        classify_route_assistant_samples([[0.0, 1.0]])


def test_route_assistant_maps_har_label_to_navigation_mode(settings, monkeypatch):
    settings.HAR_WINDOW_SAMPLE_COUNT = 2
    monkeypatch.setattr(
        route_assistant,
        "predict_window_label",
        lambda samples: ("MOVING_VEHICLE", 0.85),
    )

    result = classify_route_assistant_samples(_samples(2))

    assert result.label == "driving"
    assert result.confidence == 0.85
