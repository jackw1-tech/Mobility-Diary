from __future__ import annotations

from dataclasses import dataclass

from django.conf import settings

from shared.exceptions import ServiceError

from ..ml.har_adapter import predict_window_label


class RouteAssistantValidationError(ServiceError):
    status_code = 422


@dataclass(frozen=True)
class RouteAssistantClassification:
    label: str
    confidence: float


_ASSISTANT_MODE_BY_LABEL = {
    "IDLE": "idle",
    "WALKING": "walking",
    "RUNNING": "walking",
    "BIKING": "cycling",
    "MOVING_VEHICLE": "driving",
}


def classify_route_assistant_samples(
    samples: list[list[float]],
) -> RouteAssistantClassification:
    if len(samples) != settings.HAR_WINDOW_SAMPLE_COUNT or any(
        len(row) < 6 for row in samples
    ):
        raise RouteAssistantValidationError("finestra sensori non valida")

    label, confidence = predict_window_label(samples)
    return RouteAssistantClassification(
        label=_ASSISTANT_MODE_BY_LABEL.get(label, "idle"),
        confidence=confidence,
    )
