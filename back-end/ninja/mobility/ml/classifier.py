"""Classificatore di attivita.

Quando le finestre raw sono disponibili, `classify_windows` invoca l'adapter
Keras CNN+GRU. I modelli HAR sono obbligatori: se non sono disponibili,
l'errore risale al chiamante.
"""

from __future__ import annotations

from dataclasses import dataclass

from .har_adapter import predict_activity_windows

# Bande di velocita (m/s).
WALK_MAX = 2.2          # ~8 km/h
RUN_MAX = 3.6           # ~13 km/h
BIKE_MAX = 7.0          # ~25 km/h


@dataclass(frozen=True)
class ClassifierResult:
    labels: list[str] #Lista di Labels,una a finestra 
    summary: dict


def _label_from_speed(speed: float) -> str:
    if speed < WALK_MAX:
        return "WALKING"
    if speed < RUN_MAX:
        return "RUNNING"
    if speed < BIKE_MAX:
        return "BIKING"
    return "MOVING_VEHICLE"


""" 
Assegna i label di attività per ogni sensor window
"""
def classify_windows(
    *,
    raw_windows=None,
) -> ClassifierResult:
    prediction = predict_activity_windows(raw_windows)
    return ClassifierResult(prediction.labels, prediction.summary)
