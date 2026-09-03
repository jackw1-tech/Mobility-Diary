from __future__ import annotations

import json
from datetime import datetime, timezone as dt_timezone

import numpy as np
from django.utils.dateparse import parse_datetime

from ..ml.pipeline import PipelineSensorWindow

EXPECTED_SAMPLE_COUNT = 500
EXPECTED_CHANNEL_COUNT = 6

# Il modello HAR lavora in float32: convertire qui evita che il resto della
# pipeline debba conoscere il dtype scelto a monte.
_MATRIX_DTYPE = "<f4"


class InvalidRawSensorPayload(ValueError):
    """Il payload raw e leggibile dallo storage ma non rispetta il contratto HAR."""


"""
Mapper da payload JSON decompresso a oggetti PipelineSensorWindow.

Formato atteso (prodotto da TripPackageBuilder lato mobile):

    {"windows": [{"window_start": "...Z", "window_end": "...Z",
                  "sample_rate_hz": 100, "sample_count": 500,
                  "channel_count": 6, "samples": [[6 float] x 500]}]}
"""
def decode_sensor_windows_payload(raw: bytes) -> list[PipelineSensorWindow]:
    try:
        payload = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise InvalidRawSensorPayload("payload raw sensor non e' JSON valido") from exc

    if not isinstance(payload, dict):
        raise InvalidRawSensorPayload("payload raw sensor senza oggetto radice")
    windows = payload.get("windows")
    if not isinstance(windows, list):
        raise InvalidRawSensorPayload("payload raw sensor senza lista windows")

    return [_decode_window(window) for window in windows]


def _decode_window(window: object) -> PipelineSensorWindow:
    if not isinstance(window, dict):
        raise InvalidRawSensorPayload("sensor window non valida")

    start = _datetime_field(window, "window_start")
    end = _datetime_field(window, "window_end")
    if end <= start:
        raise InvalidRawSensorPayload(
            "sensor window con intervallo temporale non valido"
        )

    sample_rate = _int_field(window, "sample_rate_hz")
    if sample_rate <= 0:
        raise InvalidRawSensorPayload("sensor window con sample_rate_hz non valido")

    sample_count = _int_field(window, "sample_count")
    if sample_count != EXPECTED_SAMPLE_COUNT:
        raise InvalidRawSensorPayload(
            f"sensor window con sample_count diverso da {EXPECTED_SAMPLE_COUNT}"
        )

    channel_count = _int_field(window, "channel_count")
    if channel_count != EXPECTED_CHANNEL_COUNT:
        raise InvalidRawSensorPayload(
            f"sensor window con channel_count diverso da {EXPECTED_CHANNEL_COUNT}"
        )

    return PipelineSensorWindow(
        start_timestamp=start,
        end_timestamp=end,
        sample_count=sample_count,
        frequency_hz=sample_rate,
        matrix=_decode_matrix(window.get("samples"), sample_count, channel_count),
    )


def _decode_matrix(samples: object, sample_count: int, channel_count: int):
    if not isinstance(samples, list):
        raise InvalidRawSensorPayload("sensor window senza matrice samples")
    try:
        matrix = np.asarray(samples, dtype=_MATRIX_DTYPE)
    except (TypeError, ValueError) as exc:
        raise InvalidRawSensorPayload("matrice samples non numerica") from exc

    if matrix.shape != (sample_count, channel_count):
        raise InvalidRawSensorPayload(
            "matrice samples con forma diversa da "
            f"({sample_count}, {channel_count})"
        )
    if not np.isfinite(matrix).all():
        raise InvalidRawSensorPayload("matrice samples con valori non finiti")
    return matrix


def _datetime_field(window: dict, field: str) -> datetime:
    value = window.get(field)
    if not isinstance(value, str):
        raise InvalidRawSensorPayload(f"timestamp raw mancante: {field}")
    parsed = parse_datetime(value)
    if parsed is None:
        raise InvalidRawSensorPayload(f"timestamp raw non valido: {field}")
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=dt_timezone.utc)
    return parsed.astimezone(dt_timezone.utc)


def _int_field(window: dict, field: str) -> int:
    value = window.get(field)
    if isinstance(value, bool) or not isinstance(value, int):
        raise InvalidRawSensorPayload(f"campo intero raw non valido: {field}")
    return value
