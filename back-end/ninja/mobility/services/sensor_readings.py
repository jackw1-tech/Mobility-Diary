"""Persistenza delle letture inerziali grezze su TimescaleDB (ADR 0001).

La proiezione riga-per-campione alimenta query temporali, debug e valutazione
del classificatore. Nel percorso di produzione viene accodata dopo l'inferenza
HAR, cosi' il risultato AI non resta bloccato dalla scrittura Timescale.
"""

from __future__ import annotations

import struct
from datetime import datetime, timedelta, timezone

from django.conf import settings
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
    if settings.RAW_SENSOR_COPY_FORMAT.lower() == "binary":
        return _persist_raw_sensor_readings_binary(trip, windows)
    return _persist_raw_sensor_readings_text(trip, windows)


def _persist_raw_sensor_readings_text(
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


def _persist_raw_sensor_readings_binary(
    trip: Trip,
    windows: list[PipelineSensorWindow],
) -> int:
    total = 0
    table = connection.ops.quote_name(RawSensorReading._meta.db_table)
    columns = ", ".join(connection.ops.quote_name(column) for column in _INSERT_COLUMNS)
    copy_sql = f"COPY {table} ({columns}) FROM STDIN WITH (FORMAT BINARY)"

    with connection.cursor() as cursor:
        raw_cursor = getattr(cursor, "cursor", cursor)
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


def _raw_sensor_reading_binary_row(
    trip_id: int,
    timestamp_us: int,
    row,
) -> bytes:
    buffer = bytearray()
    _append_raw_sensor_reading_binary_row(buffer, trip_id, timestamp_us, row)
    return bytes(buffer)


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
