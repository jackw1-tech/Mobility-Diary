from __future__ import annotations

import struct
from datetime import datetime, timezone as dt_timezone
from enum import Enum

import numpy as np

from ..ml.pipeline import PipelineSensorWindow


class InvalidRawSensorPayload(ValueError):
    """Il blob raw e leggibile dallo storage ma non rispetta il contratto HAR."""


class RawSensorPayloadFormat(str, Enum):
    BINARY = "binary"
    JSON = "json"


_RAW_SENSOR_BINARY_MAGIC = b"MDHARW1\x00"
_RAW_SENSOR_BINARY_PREFIX = b"MDHAR"
_RAW_SENSOR_BINARY_HEADER = struct.Struct("<8sI")
_RAW_SENSOR_BINARY_WINDOW_HEADER = struct.Struct("<qqIII")


def raw_sensor_payload_format(raw: bytes) -> RawSensorPayloadFormat:
    if raw.startswith(_RAW_SENSOR_BINARY_PREFIX):
        return RawSensorPayloadFormat.BINARY
    return RawSensorPayloadFormat.JSON

"""
Mapper da dati da byte grezzi decompressi a oggetti PipelineSensorWindow
"""
def decode_sensor_windows_payload(raw: bytes) -> list[PipelineSensorWindow]:
    return _decode_binary_sensor_windows(raw)


def _datetime_from_epoch_micros(value: int, field: str) -> datetime:
    try:
        seconds, micros = divmod(int(value), 1_000_000)
        return datetime.fromtimestamp(seconds, tz=dt_timezone.utc).replace(
            microsecond=micros
        )
    except (OSError, OverflowError, ValueError) as exc:
        raise InvalidRawSensorPayload(f"timestamp raw non valido: {field}") from exc

"""
Funzione che decodifica i raw sensor windows grezzi in oggetti PipelineSensorWindow
"""
def _decode_binary_sensor_windows(raw: bytes) -> list[PipelineSensorWindow]:
    if len(raw) < _RAW_SENSOR_BINARY_HEADER.size:
        raise InvalidRawSensorPayload("payload raw sensor binario incompleto")

    magic, window_count = _RAW_SENSOR_BINARY_HEADER.unpack_from(raw, 0)
    if magic != _RAW_SENSOR_BINARY_MAGIC:
        raise InvalidRawSensorPayload("payload raw sensor binario non valido")

    cursor = _RAW_SENSOR_BINARY_HEADER.size
    windows: list[PipelineSensorWindow] = []
    try:
        for _index in range(window_count):
            if cursor + _RAW_SENSOR_BINARY_WINDOW_HEADER.size > len(raw):
                raise InvalidRawSensorPayload("payload raw sensor binario troncato")
            (
                start_us,
                end_us,
                sample_rate,
                sample_count,
                channel_count,
            ) = _RAW_SENSOR_BINARY_WINDOW_HEADER.unpack_from(raw, cursor)
            cursor += _RAW_SENSOR_BINARY_WINDOW_HEADER.size

            start = _datetime_from_epoch_micros(start_us, "window_start")
            end = _datetime_from_epoch_micros(end_us, "window_end")
            if end <= start:
                raise InvalidRawSensorPayload(
                    "sensor window con intervallo temporale non valido"
                )
            if sample_rate <= 0:
                raise InvalidRawSensorPayload(
                    "sensor window con sample_rate_hz non valido"
                )
            if sample_count != 500:
                raise InvalidRawSensorPayload(
                    "sensor window con sample_count diverso da 500"
                )
            if channel_count != 6:
                raise InvalidRawSensorPayload(
                    "sensor window con channel_count diverso da 6"
                )

            value_count = sample_count * channel_count
            value_bytes = value_count * np.dtype("<f4").itemsize
            if cursor + value_bytes > len(raw):
                raise InvalidRawSensorPayload("payload raw sensor binario troncato")
            matrix = np.frombuffer(
                raw,
                dtype="<f4",
                count=value_count,
                offset=cursor,
            ).reshape((sample_count, channel_count))
            cursor += value_bytes
            windows.append(
                PipelineSensorWindow(
                    start_timestamp=start,
                    end_timestamp=end,
                    sample_count=sample_count,
                    frequency_hz=sample_rate,
                    matrix=matrix,
                )
            )
    except InvalidRawSensorPayload:
        raise
    except (struct.error, ValueError) as exc:
        raise InvalidRawSensorPayload("payload raw sensor binario non valido") from exc

    if cursor != len(raw):
        raise InvalidRawSensorPayload("payload raw sensor binario con byte extra")
    return windows
