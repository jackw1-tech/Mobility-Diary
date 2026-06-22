"""Classificatore di attivita.

Quando le finestre raw sono disponibili, `classify_windows` invoca l'adapter
Keras CNN+GRU. Se il modello non e disponibile e `HAR_MODEL_REQUIRED` e falso,
usa una classificazione a bande di velocita GPS come fallback esplicito.

`correct_idle_with_gps` e gia la fusione GPS definitiva: corregge le finestre
IDLE circondate da velocita da veicolo (IDLE<->MOVING_VEHICLE), il difetto #1
del modello inerziale (vedi RELAZIONE HAR).
"""

from __future__ import annotations

from dataclasses import dataclass

from django.conf import settings

from .har_adapter import HarModelUnavailable, predict_activity_windows

# Bande di velocita (m/s). Soglie da motivare in relazione.
WALK_MAX = 2.2          # ~8 km/h
RUN_MAX = 3.6           # ~13 km/h
BIKE_MAX = 7.0          # ~25 km/h
VEHICLE_SPEED_MPS = 8.0  # ~29 km/h: chiaramente un veicolo
CONTEXT = 6              # +-6 finestre = +-30s di contesto


@dataclass(frozen=True)
class ClassifierResult:
    labels: list[str]
    summary: dict


def _label_from_speed(speed: float | None) -> str:
    if speed is None or speed < 0.5:
        return "IDLE"
    if speed < WALK_MAX:
        return "WALKING"
    if speed < RUN_MAX:
        return "RUNNING"
    if speed < BIKE_MAX:
        return "BIKING"
    return "MOVING_VEHICLE"


def _speed_fallback_summary(reason: str | None = None) -> dict:
    summary = {"classifier": "placeholder_gps_speed"}
    if reason:
        summary["fallback_reason"] = reason
    return summary


def classify_windows(
    normalized_windows,
    win_speeds: list[float | None],
    *,
    raw_windows=None,
) -> ClassifierResult:
    if raw_windows:
        try:
            prediction = predict_activity_windows(raw_windows)
        except HarModelUnavailable as exc:
            if settings.HAR_MODEL_REQUIRED:
                raise
            labels = [_label_from_speed(s) for s in win_speeds]
            return ClassifierResult(labels, _speed_fallback_summary(str(exc)))
        if len(prediction.labels) != len(win_speeds):
            raise ValueError("il classificatore HAR ha restituito un numero di label errato")
        return ClassifierResult(prediction.labels, prediction.summary)

    labels = [_label_from_speed(s) for s in win_speeds]
    return ClassifierResult(labels, _speed_fallback_summary())


def correct_idle_with_gps(labels: list[str], win_speeds: list[float | None]) -> list[str]:
    out = list(labels)
    n = len(out)
    for i in range(n):
        if out[i] != "IDLE":
            continue
        lo, hi = max(0, i - CONTEXT), min(n, i + CONTEXT + 1)
        near = [s for s in win_speeds[lo:hi] if s is not None]
        if near and max(near) >= VEHICLE_SPEED_MPS:
            out[i] = "MOVING_VEHICLE"  # eri in viaggio: il "fermo" era un semaforo
    return out
