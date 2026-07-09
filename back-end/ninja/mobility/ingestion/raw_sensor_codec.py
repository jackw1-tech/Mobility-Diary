from __future__ import annotations

import json
import struct
from datetime import datetime, timezone as dt_timezone
from enum import Enum
from typing import Any

import numpy as np
from django.utils.dateparse import parse_datetime

from ..ml.pipeline import PipelineSensorWindow

try:
    import orjson
except ModuleNotFoundError:  # pragma: no cover - fallback per ambienti non rebuildati
    orjson = None


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


def decode_sensor_windows_payload(raw: bytes) -> list[PipelineSensorWindow]:
    match raw_sensor_payload_format(raw):
        case RawSensorPayloadFormat.BINARY:
            return _decode_binary_sensor_windows(raw)
        case RawSensorPayloadFormat.JSON:
            return _decode_json_sensor_windows(raw)


def _load_json_bytes(raw: bytes) -> Any:
    if orjson is not None:
        return orjson.loads(raw)
    return json.loads(raw.decode("utf-8"))


def _datetime_from_epoch_micros(value: int, field: str) -> datetime:
    try:
        seconds, micros = divmod(int(value), 1_000_000)
        return datetime.fromtimestamp(seconds, tz=dt_timezone.utc).replace(
            microsecond=micros
        )
    except (OSError, OverflowError, ValueError) as exc:
        raise InvalidRawSensorPayload(f"timestamp raw non valido: {field}") from exc


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


def _decode_json_sensor_windows(raw: bytes) -> list[PipelineSensorWindow]:
    try:
        payload = _load_json_bytes(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise InvalidRawSensorPayload("payload raw sensor JSON non valido") from exc

    raw_windows = payload.get("windows") if isinstance(payload, dict) else payload
    if not isinstance(raw_windows, list):
        raise InvalidRawSensorPayload("payload raw sensor senza lista windows")
    return [_parse_sensor_window(raw_window) for raw_window in raw_windows]


def _parse_required_datetime(value: Any, field: str):
    parsed = parse_datetime(str(value)) if value else None
    if parsed is None:
        raise InvalidRawSensorPayload(f"timestamp raw non valido: {field}")
    return parsed


def _window_matrix(raw_window: dict) -> list[list[float]]:
    matrix = raw_window.get("samples", raw_window.get("matrix"))
    if not isinstance(matrix, list) or not matrix:
        raise InvalidRawSensorPayload("sensor window senza matrice samples/matrix")
    normalized: list[list[float]] = []
    for row in matrix:
        if not isinstance(row, list) or len(row) < 6:
            raise InvalidRawSensorPayload("sensor window con riga matrice non valida")
        try:
            normalized.append([float(value) for value in row[:6]])
        except (TypeError, ValueError) as exc:
            raise InvalidRawSensorPayload(
                "sensor window con valore matrice non numerico"
            ) from exc
    return normalized


def _parse_sensor_window(raw_window: dict) -> PipelineSensorWindow:
    start = _parse_required_datetime(
        raw_window.get("window_start", raw_window.get("start")),
        "window_start",
    )
    end = _parse_required_datetime(
        raw_window.get("window_end", raw_window.get("end")),
        "window_end",
    )
    if end <= start:
        raise InvalidRawSensorPayload(
            "sensor window con intervallo temporale non valido"
        )

    try:
        sample_rate = int(
            raw_window.get("sample_rate_hz", raw_window.get("frequency_hz", 0))
        )
    except (TypeError, ValueError) as exc:
        raise InvalidRawSensorPayload(
            "sensor window con sample_rate_hz non valido"
        ) from exc
    if sample_rate <= 0:
        raise InvalidRawSensorPayload("sensor window con sample_rate_hz non valido")

    matrix = _window_matrix(raw_window)
    try:
        sample_count = int(raw_window.get("sample_count", len(matrix)))
    except (TypeError, ValueError) as exc:
        raise InvalidRawSensorPayload(
            "sensor window con sample_count non valido"
        ) from exc
    if sample_count != len(matrix):
        raise InvalidRawSensorPayload("sensor window con sample_count incoerente")
    if sample_count != 500:
        raise InvalidRawSensorPayload("sensor window con sample_count diverso da 500")

    return PipelineSensorWindow(
        start_timestamp=start,
        end_timestamp=end,
        sample_count=sample_count,
        frequency_hz=sample_rate,
        matrix=matrix,
    )
