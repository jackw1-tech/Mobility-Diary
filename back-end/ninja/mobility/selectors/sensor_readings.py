"""Repository di scrittura della proiezione Timescale RawSensorReading.

La persistenza iniziale usa COPY binario; i viaggi derivati possono invece
clonare le righe del sorgente con INSERT ... SELECT interamente in Postgres.
"""

from __future__ import annotations

import struct
from datetime import datetime, timedelta, timezone

from django.db import connection, transaction

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
_POSTGRES_BINARY_COPY_HEADER = b"PGCOPY\n\xff\r\n\x00" + struct.pack("!II", 0, 0)
_POSTGRES_BINARY_COPY_TRAILER = struct.pack("!h", -1)
_POSTGRES_EPOCH = datetime(2000, 1, 1, tzinfo=timezone.utc)
_COPY_BINARY_ROW_PREFIX = struct.pack("!h", len(_INSERT_COLUMNS))
_COPY_BINARY_FIELD_LENGTH = struct.pack("!i", 8)
_COPY_BINARY_CHUNK_BYTES = 1024 * 1024
_INT64 = struct.Struct("!q")
_FLOAT64 = struct.Struct("!d")


def persist_raw_sensor_readings(
    trip: Trip,
    windows: list[PipelineSensorWindow],
) -> int:
    total = 0
    table = connection.ops.quote_name(RawSensorReading._meta.db_table)
    columns = ", ".join(connection.ops.quote_name(column) for column in _INSERT_COLUMNS)
    copy_sql = f"COPY {table} ({columns}) FROM STDIN WITH (FORMAT BINARY)"

    with connection.cursor() as cursor:
        raw_cursor = cursor.cursor
        with raw_cursor.copy(copy_sql) as copy:
            buffer = bytearray(_POSTGRES_BINARY_COPY_HEADER)
            for window in windows:
                period_us = _timedelta_micros(
                    timedelta(seconds=1.0 / window.frequency_hz)
                )
                start_us = _postgres_timestamp_micros(window.start_timestamp)
                for index, row in enumerate(window.matrix):
                    _append_raw_sensor_reading_binary_row(
                        buffer,
                        trip.id,
                        start_us + index * period_us,
                        row,
                    )
                    total += 1
                    if len(buffer) >= _COPY_BINARY_CHUNK_BYTES:
                        copy.write(buffer)
                        buffer.clear()
            buffer.extend(_POSTGRES_BINARY_COPY_TRAILER)
            copy.write(buffer)
    return total


def replace_raw_sensor_readings(
    trip: Trip,
    windows: list[PipelineSensorWindow],
) -> int:
    """Ricostruisce idempotentemente la proiezione Timescale di un viaggio."""
    with transaction.atomic():
        RawSensorReading.objects.filter(trip=trip).delete()
        return persist_raw_sensor_readings(trip, windows)


def replace_raw_sensor_readings_from_source(
    trip: Trip,
    source: Trip,
    *,
    shift: timedelta,
    start: datetime | None = None,
    end: datetime | None = None,
) -> int:
    """Clona la proiezione Timescale di un derivato restando dentro Postgres.

    Le righe di un viaggio ricaricato sono le stesse del sorgente, solo
    traslate nel tempo: leggerle da object storage, decodificarle in Python e
    riscriverle con COPY significa far attraversare al processo centinaia di
    migliaia di righe che il database ha gia'. Un INSERT ... SELECT le sposta
    senza uscire dal server. [start, end] limita la copia alla finestra
    effettiva del derivato (Riproduzione Live tronca allo Stop).
    """
    table = connection.ops.quote_name(RawSensorReading._meta.db_table)
    columns = ", ".join(connection.ops.quote_name(column) for column in _INSERT_COLUMNS)
    value_columns = ", ".join(
        connection.ops.quote_name(column) for column in _INSERT_COLUMNS[2:]
    )
    trip_id_column = connection.ops.quote_name(_INSERT_COLUMNS[0])
    timestamp_column = connection.ops.quote_name(_INSERT_COLUMNS[1])

    conditions = [f"{trip_id_column} = %s"]
    params: list[object] = [trip.id, shift, source.id]
    if start is not None:
        conditions.append(f"{timestamp_column} + %s >= %s")
        params.extend([shift, start])
    if end is not None:
        conditions.append(f"{timestamp_column} + %s <= %s")
        params.extend([shift, end])

    sql = (
        f"INSERT INTO {table} ({columns}) "
        f"SELECT %s, {timestamp_column} + %s, {value_columns} "
        f"FROM {table} WHERE {' AND '.join(conditions)}"
    )

    with transaction.atomic():
        RawSensorReading.objects.filter(trip=trip).delete()
        with connection.cursor() as cursor:
            cursor.execute(sql, params)
            return cursor.rowcount


def _append_raw_sensor_reading_binary_row(
    buffer: bytearray,
    trip_id: int,
    timestamp_us: int,
    row,
) -> None:
    buffer.extend(_COPY_BINARY_ROW_PREFIX)
    _append_int64_field(buffer, trip_id)
    _append_int64_field(buffer, timestamp_us)
    for index in range(6):
        _append_float64_field(buffer, float(row[index]))


def _append_int64_field(buffer: bytearray, value: int) -> None:
    buffer.extend(_COPY_BINARY_FIELD_LENGTH)
    buffer.extend(_INT64.pack(int(value)))


def _append_float64_field(buffer: bytearray, value: float) -> None:
    buffer.extend(_COPY_BINARY_FIELD_LENGTH)
    buffer.extend(_FLOAT64.pack(value))


def _postgres_timestamp_micros(value: datetime) -> int:
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    delta = value.astimezone(timezone.utc) - _POSTGRES_EPOCH
    return _timedelta_micros(delta)


def _timedelta_micros(value: timedelta) -> int:
    return (
        value.days * 24 * 60 * 60 * 1_000_000
        + value.seconds * 1_000_000
        + value.microseconds
    )
