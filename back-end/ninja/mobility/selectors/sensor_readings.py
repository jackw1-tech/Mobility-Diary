"""Rilettura delle letture inerziali grezze da TimescaleDB (ADR 0001).

Per i consumatori che non hanno gia' le finestre in memoria (script di
valutazione HAR, riprocessamenti manuali). Il task HAR di produzione non
passa da qui: usa direttamente gli array appena decodificati dai blob.
"""

from __future__ import annotations

import numpy as np

from ..ml.pipeline import PipelineSensorWindow
from ..models import RawSensorReading

_SAMPLES_PER_WINDOW = 500
_MAX_GAP_SECONDS = 1.0

_VALUE_FIELDS = (
    "timestamp",
    "accel_x",
    "accel_y",
    "accel_z",
    "gyro_x",
    "gyro_y",
    "gyro_z",
)


def load_trip_windows_from_db(
    trip_id: int,
    *,
    samples_per_window: int = _SAMPLES_PER_WINDOW,
) -> list[PipelineSensorWindow]:
    """Ricostruisce finestre contigue da N campioni a partire dalle righe ordinate.

    Un buco temporale superiore a _MAX_GAP_SECONDS chiude il tratto corrente
    (stessa filosofia dello stay-point detection): i tratti vengono poi
    suddivisi in finestre piene, scartando l'eventuale coda incompleta.
    """
    rows = list(
        RawSensorReading.objects.filter(trip_id=trip_id)
        .order_by("timestamp")
        .values_list(*_VALUE_FIELDS)
    )
    windows: list[PipelineSensorWindow] = []
    for run in _contiguous_runs(rows):
        windows.extend(_chunk_run(run, samples_per_window))
    return windows


def _contiguous_runs(rows: list[tuple]) -> list[list[tuple]]:
    """Spezza le righe ordinate in tratti senza buchi temporali."""
    runs: list[list[tuple]] = []
    current: list[tuple] = []
    previous_ts = None
    for row in rows:
        ts = row[0]
        if (
            previous_ts is not None
            and (ts - previous_ts).total_seconds() > _MAX_GAP_SECONDS
        ):
            runs.append(current)
            current = []
        current.append(row)
        previous_ts = ts
    if current:
        runs.append(current)
    return runs


def _chunk_run(run: list[tuple], samples_per_window: int) -> list[PipelineSensorWindow]:
    """Divide un tratto contiguo in finestre piene da samples_per_window campioni."""
    windows: list[PipelineSensorWindow] = []
    for offset in range(0, len(run) - samples_per_window + 1, samples_per_window):
        chunk = run[offset : offset + samples_per_window]
        start = chunk[0][0]
        end = chunk[-1][0]
        duration = (end - start).total_seconds()
        frequency = (
            round((samples_per_window - 1) / duration) if duration > 0 else 0
        )
        matrix = np.array([row[1:] for row in chunk], dtype=np.float32)
        windows.append(
            PipelineSensorWindow(
                start_timestamp=start,
                end_timestamp=end,
                sample_count=samples_per_window,
                frequency_hz=frequency,
                matrix=matrix,
            )
        )
    return windows
