"""Classificatore di attivita.

PLACEHOLDER: finche il modello `.keras` (CNN 9ch + GRU) non e disponibile,
`classify_windows` usa una semplice classificazione a bande di velocita GPS
(il livello HAR "base" ammesso dalla traccia). Le matrici normalizzate vengono
comunque calcolate a monte (preprocessing reale) e passate qui: il modello vero
le usera al posto della velocita, senza cambiare il resto della pipeline.

`correct_idle_with_gps` e gia la fusione GPS definitiva: corregge le finestre
IDLE circondate da velocita da veicolo (IDLE<->MOVING_VEHICLE), il difetto #1
del modello inerziale (vedi RELAZIONE HAR).
"""

from __future__ import annotations

# Bande di velocita (m/s). Soglie da motivare in relazione.
WALK_MAX = 2.2          # ~8 km/h
RUN_MAX = 3.6           # ~13 km/h
BIKE_MAX = 7.0          # ~25 km/h
VEHICLE_SPEED_MPS = 8.0  # ~29 km/h: chiaramente un veicolo
CONTEXT = 6              # +-6 finestre = +-30s di contesto


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


def classify_windows(normalized_windows, win_speeds: list[float | None]) -> list[str]:
    # PLACEHOLDER. Il modello reale classifichera `normalized_windows` (CNN->GRU).
    return [_label_from_speed(s) for s in win_speeds]


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
