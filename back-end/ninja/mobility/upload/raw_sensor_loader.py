from __future__ import annotations

import gzip

from ..ml.pipeline import PipelineSensorWindow
from ..models import TripUpload
from ..raw_sensor_windows_cache import (
    cache_raw_sensor_windows,
    get_cached_raw_sensor_windows,
)
from . import storage
from .raw_sensor_codec import (
    InvalidRawSensorPayload,
    decode_sensor_windows_payload,
)


"""
Dato il trip, mette tutte insieme le sensor window
"""
def load_raw_sensor_windows(
    upload: TripUpload,
) -> list[PipelineSensorWindow]:
    cached_windows = get_cached_raw_sensor_windows(upload.id)
    if cached_windows is not None:
        return cached_windows

    parts = list(
        upload.parts.filter(
            received_at__isnull=False,
        ).order_by("sequence")
    )

    windows: list[PipelineSensorWindow] = []
    for part in parts:
        windows.extend(_load_raw_sensor_part_windows(part.object_key))

    windows = sorted(windows, key=lambda window: window.start_timestamp)

    cache_raw_sensor_windows(upload.id, windows)
    return windows

"""
Scarica dall'object storage l'oggetto
"""
def _load_raw_sensor_part_windows(
    object_key: str,
) -> list[PipelineSensorWindow]:
    raw = storage.read_object(object_key)

    try:
        decompressed = gzip.decompress(raw)
    except (gzip.BadGzipFile, EOFError) as exc:
        raise InvalidRawSensorPayload("payload raw sensor gzip non valido") from exc

    return decode_sensor_windows_payload(decompressed)
