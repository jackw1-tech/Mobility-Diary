from __future__ import annotations

import gzip
import time
from typing import Any

from ..ml.pipeline import PipelineSensorWindow
from ..models import PartKind, TripIngestion
from . import storage
from .raw_sensor_codec import (
    InvalidRawSensorPayload,
    RawSensorPayloadFormat,
    decode_sensor_windows_payload,
    raw_sensor_payload_format,
)


def load_raw_sensor_windows(
    ingestion: TripIngestion,
    timings: dict[str, Any] | None = None,
) -> list[PipelineSensorWindow]:
    parts_start = time.perf_counter()
    parts = list(
        ingestion.parts.filter(
            kind=PartKind.SENSOR_WINDOWS,
            received_at__isnull=False,
        ).order_by("sequence")
    )
    _add_elapsed_ms(timings, "raw_parts_query_ms", parts_start)
    if timings is not None:
        timings["raw_parts"] = len(parts)

    windows: list[PipelineSensorWindow] = []
    for part in parts:
        windows.extend(_load_raw_sensor_part_windows(part.object_key, timings=timings))

    sort_start = time.perf_counter()
    sorted_windows = sorted(windows, key=lambda window: window.start_timestamp)
    _add_elapsed_ms(timings, "raw_sort_ms", sort_start)
    if timings is not None:
        timings["raw_windows"] = len(sorted_windows)
    return sorted_windows


def _load_raw_sensor_part_windows(
    object_key: str,
    timings: dict[str, Any] | None = None,
) -> list[PipelineSensorWindow]:
    decompressed = _read_gzip_object(object_key, timings=timings)
    payload_format = raw_sensor_payload_format(decompressed)
    decode_start = time.perf_counter()
    windows = decode_sensor_windows_payload(decompressed)
    timing_key = (
        "raw_binary_decode_ms"
        if payload_format == RawSensorPayloadFormat.BINARY
        else "raw_window_parse_ms"
    )
    _add_elapsed_ms(timings, timing_key, decode_start)
    return windows


def _read_gzip_object(object_key: str, timings: dict[str, Any] | None = None) -> bytes:
    read_start = time.perf_counter()
    raw = storage.read_object(object_key)
    _add_elapsed_ms(timings, "raw_s3_read_ms", read_start)
    try:
        gzip_start = time.perf_counter()
        decompressed = gzip.decompress(raw)
        _add_elapsed_ms(timings, "raw_gzip_ms", gzip_start)
        return decompressed
    except (gzip.BadGzipFile, EOFError) as exc:
        raise InvalidRawSensorPayload("payload raw sensor gzip non valido") from exc


def _add_elapsed_ms(timings: dict[str, Any] | None, key: str, start: float) -> None:
    if timings is None:
        return
    elapsed = (time.perf_counter() - start) * 1000
    timings[key] = round(float(timings.get(key, 0.0)) + elapsed, 2)
