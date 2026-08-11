"""Repository del RawSensorReading (proiezione TimescaleDB, ADR 0001).

Unico punto del progetto in cui compare `RawSensorReading.objects`, sia in
lettura (per i consumatori che non hanno gia' le finestre in memoria: script
di valutazione HAR, riprocessamenti manuali) sia in scrittura (persistenza
bulk via COPY, accodata dopo l'inferenza HAR di produzione).

Prima di questo merge lettura e scrittura di RawSensorReading vivevano in due
moduli separati (`selectors.sensor_readings` per le letture e
`services.sensor_readings` per le scritture), nonostante nessuno dei due
contenesse business logic: erano gia' entrambi un repository, solo con un
nome diverso (violazione di naming/coerenza, non di layer).
"""

from __future__ import annotations

import struct
from datetime import datetime, timedelta, timezone

import numpy as np
from django.conf import settings
from django.db import connection, transaction

from ..ml.pipeline import PipelineSensorWindow
from ..models import RawSensorReading, Trip

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
