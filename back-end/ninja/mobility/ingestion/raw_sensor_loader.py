from __future__ import annotations

import gzip

from ..ml.pipeline import PipelineSensorWindow
from ..models import TripIngestion
from . import storage
from .raw_sensor_codec import (
    InvalidRawSensorPayload,
    decode_sensor_windows_payload,
)

""" 
Dato il trip, ne estrae tutte le trip ingestion completate (receivet at not null)
Mette tutte insieme le sensor window
"""
def load_raw_sensor_windows(
    ingestion: TripIngestion,
) -> list[PipelineSensorWindow]:
    parts = list(
        ingestion.parts.filter(
            received_at__isnull=False,
        ).order_by("sequence")
    )

    windows: list[PipelineSensorWindow] = []
    for part in parts:
        windows.extend(_load_raw_sensor_part_windows(part.object_key))

    return sorted(windows, key=lambda window: window.start_timestamp)


def _load_raw_sensor_part_windows(
    object_key: str,
) -> list[PipelineSensorWindow]:
    decompressed = _read_gzip_object(object_key)
    return decode_sensor_windows_payload(decompressed)


def _read_gzip_object(object_key: str) -> bytes:
    raw = storage.read_object(object_key)
    try:
        return gzip.decompress(raw)
    except (gzip.BadGzipFile, EOFError) as exc:
        raise InvalidRawSensorPayload("payload raw sensor gzip non valido") from exc
