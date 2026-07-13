from __future__ import annotations

import gzip
from dataclasses import dataclass, field
from time import perf_counter

from ..ml.pipeline import PipelineSensorWindow
from ..models import TripIngestion
from . import storage
from .raw_sensor_codec import (
    InvalidRawSensorPayload,
    decode_sensor_windows_payload,
)


@dataclass(frozen=True)
class RawSensorLoadResult:
    windows: list[PipelineSensorWindow]
    part_count: int
    compressed_bytes: int
    decompressed_bytes: int
    timings_ms: dict[str, float] = field(default_factory=dict)


""" 
Dato il trip, ne estrae tutte le trip ingestion completate (receivet at not null)
Mette tutte insieme le sensor window
"""
def load_raw_sensor_windows(
    ingestion: TripIngestion,
) -> list[PipelineSensorWindow]:
    return load_raw_sensor_windows_with_metrics(ingestion).windows


def load_raw_sensor_windows_with_metrics(
    ingestion: TripIngestion,
) -> RawSensorLoadResult:
    parts = list(
        ingestion.parts.filter(
            received_at__isnull=False,
        ).order_by("sequence")
    )

    windows: list[PipelineSensorWindow] = []
    compressed_bytes = 0
    decompressed_bytes = 0
    timings_ms = {
        "storage_read": 0.0,
        "gzip_decompress": 0.0,
        "payload_decode": 0.0,
        "sort_windows": 0.0,
    }
    for part in parts:
        part_result = _load_raw_sensor_part_windows_with_metrics(part.object_key)
        windows.extend(part_result.windows)
        compressed_bytes += part_result.compressed_bytes
        decompressed_bytes += part_result.decompressed_bytes
        for key, value in part_result.timings_ms.items():
            timings_ms[key] = timings_ms.get(key, 0.0) + value

    sort_started = perf_counter()
    windows = sorted(windows, key=lambda window: window.start_timestamp)
    timings_ms["sort_windows"] += _elapsed_ms(sort_started)

    return RawSensorLoadResult(
        windows=windows,
        part_count=len(parts),
        compressed_bytes=compressed_bytes,
        decompressed_bytes=decompressed_bytes,
        timings_ms=timings_ms,
    )


def _load_raw_sensor_part_windows(
    object_key: str,
) -> list[PipelineSensorWindow]:
    return _load_raw_sensor_part_windows_with_metrics(object_key).windows


def _load_raw_sensor_part_windows_with_metrics(
    object_key: str,
) -> RawSensorLoadResult:
    read_started = perf_counter()
    raw = storage.read_object(object_key)
    storage_read_ms = _elapsed_ms(read_started)

    decompress_started = perf_counter()
    try:
        decompressed = gzip.decompress(raw)
    except (gzip.BadGzipFile, EOFError) as exc:
        raise InvalidRawSensorPayload("payload raw sensor gzip non valido") from exc
    gzip_decompress_ms = _elapsed_ms(decompress_started)

    decode_started = perf_counter()
    windows = decode_sensor_windows_payload(decompressed)
    payload_decode_ms = _elapsed_ms(decode_started)

    return RawSensorLoadResult(
        windows=windows,
        part_count=1,
        compressed_bytes=len(raw),
        decompressed_bytes=len(decompressed),
        timings_ms={
            "storage_read": storage_read_ms,
            "gzip_decompress": gzip_decompress_ms,
            "payload_decode": payload_decode_ms,
        },
    )


def _read_gzip_object(object_key: str) -> bytes:
    raw = storage.read_object(object_key)
    try:
        return gzip.decompress(raw)
    except (gzip.BadGzipFile, EOFError) as exc:
        raise InvalidRawSensorPayload("payload raw sensor gzip non valido") from exc


def _elapsed_ms(started_at: float) -> float:
    return (perf_counter() - started_at) * 1000
