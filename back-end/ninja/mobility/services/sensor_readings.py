"""Persistenza delle letture inerziali grezze su TimescaleDB (ADR 0001).

Dual-write in stile feature store: lo stesso array decodificato dai blob
alimenta subito l'inferenza HAR (percorso "online", in memoria) e viene
proiettato qui riga-per-campione (percorso "offline") per query temporali,
debug e valutazione del classificatore. Il task non rilegge mai cio' che
ha appena scritto.
"""

from __future__ import annotations

from datetime import timedelta

from django.db import connection

from ..ml.pipeline import PipelineSensorWindow
from ..models import RawSensorReading, Trip

_INSERT_COLUMNS = (
    "trip_id",
    "timestamp",
    "accel_x",
    "accel_y",
    "accel_z",
    "gyro_x",
    "gyro_y",
    "gyro_z",
)
_VALUES_PER_ROW = len(_INSERT_COLUMNS)
_MAX_POSTGRES_PARAMETERS = 65535
_INSERT_BATCH_SIZE = min(8000, _MAX_POSTGRES_PARAMETERS // _VALUES_PER_ROW)


def persist_raw_sensor_readings(
    trip: Trip,
    windows: list[PipelineSensorWindow],
) -> int:
    pending: list[tuple] = []
    total = 0
    for window in windows:
        period = timedelta(seconds=1.0 / window.frequency_hz)
        for index, row in enumerate(window.matrix):
            pending.append(
                (
                    trip.id,
                    window.start_timestamp + index * period,
                    float(row[0]),
                    float(row[1]),
                    float(row[2]),
                    float(row[3]),
                    float(row[4]),
                    float(row[5]),
                )
            )
        if len(pending) >= _INSERT_BATCH_SIZE:
            total += _flush(pending)
            pending = []
    total += _flush(pending)
    return total


def _flush(readings: list[tuple]) -> int:
    if not readings:
        return 0
    table = connection.ops.quote_name(RawSensorReading._meta.db_table)
    columns = ", ".join(connection.ops.quote_name(column) for column in _INSERT_COLUMNS)
    row_placeholder = "(" + ", ".join(["%s"] * _VALUES_PER_ROW) + ")"
    placeholders = ", ".join([row_placeholder] * len(readings))
    params = [value for reading in readings for value in reading]
    with connection.cursor() as cursor:
        cursor.execute(
            f"""
            INSERT INTO {table} ({columns})
            VALUES {placeholders}
            ON CONFLICT DO NOTHING
            """,
            params,
        )
    return len(readings)
