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


def persist_raw_sensor_readings(
    trip: Trip,
    windows: list[PipelineSensorWindow],
) -> int:
    total = 0
    table = connection.ops.quote_name(RawSensorReading._meta.db_table)
    columns = ", ".join(connection.ops.quote_name(column) for column in _INSERT_COLUMNS)
    copy_sql = f"COPY {table} ({columns}) FROM STDIN"

    with connection.cursor() as cursor:
        raw_cursor = getattr(cursor, "cursor", cursor)
        with raw_cursor.copy(copy_sql) as copy:
            for window in windows:
                period = timedelta(seconds=1.0 / window.frequency_hz)
                for index, row in enumerate(window.matrix):
                    copy.write_row(
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
                    total += 1
    return total
