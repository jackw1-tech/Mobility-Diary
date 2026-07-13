"""Persistenza delle letture inerziali grezze su TimescaleDB (ADR 0001).

Dual-write in stile feature store: lo stesso array decodificato dai blob
alimenta subito l'inferenza HAR (percorso "online", in memoria) e viene
proiettato qui riga-per-campione (percorso "offline") per query temporali,
debug e valutazione del classificatore. Il task non rilegge mai cio' che
ha appena scritto.
"""

from __future__ import annotations

from datetime import timedelta

from ..ml.pipeline import PipelineSensorWindow
from ..models import RawSensorReading, Trip

_BULK_BATCH_SIZE = 5000


def persist_raw_sensor_readings(
    trip: Trip,
    windows: list[PipelineSensorWindow],
) -> int:
    pending: list[RawSensorReading] = []
    total = 0
    for window in windows:
        period = timedelta(seconds=1.0 / window.frequency_hz)
        for index, row in enumerate(window.matrix):
            pending.append(
                RawSensorReading(
                    trip_id=trip.id,
                    timestamp=window.start_timestamp + index * period,
                    accel_x=float(row[0]),
                    accel_y=float(row[1]),
                    accel_z=float(row[2]),
                    gyro_x=float(row[3]),
                    gyro_y=float(row[4]),
                    gyro_z=float(row[5]),
                )
            )
        if len(pending) >= _BULK_BATCH_SIZE:
            total += _flush(pending)
            pending = []
    total += _flush(pending)
    return total


def _flush(readings: list[RawSensorReading]) -> int:
    if not readings:
        return 0
    RawSensorReading.objects.bulk_create(
        readings,
        batch_size=_BULK_BATCH_SIZE,
        ignore_conflicts=True,
    )
    return len(readings)
