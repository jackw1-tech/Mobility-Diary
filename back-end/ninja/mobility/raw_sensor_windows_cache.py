from __future__ import annotations

import pickle
from typing import TYPE_CHECKING

from django.conf import settings
from redis import Redis
from redis.exceptions import RedisError

if TYPE_CHECKING:
    from .ml.pipeline import PipelineSensorWindow


def _cache_key(upload_id: int) -> str:
    return f"raw_sensor_windows:{upload_id}"


def _get_redis_client() -> Redis:
    return Redis.from_url(settings.REDIS_URL, decode_responses=False)


def get_cached_raw_sensor_windows(
    upload_id: int,
) -> "list[PipelineSensorWindow] | None":
    """Cerca in cache le sensor window raw gia' decodificate."""
    try:
        raw = _get_redis_client().get(_cache_key(upload_id))
    except RedisError:
        return None
    if raw is None:
        return None
    try:
        return pickle.loads(raw)
    except (pickle.PickleError, EOFError, TypeError, ValueError,
            ImportError, AttributeError):
        return None


def cache_raw_sensor_windows(
    upload_id: int, windows: "list[PipelineSensorWindow]"
) -> None:
    """Inserisce in cache le sensor window raw decodificate."""
    if not windows:
        return
    ttl = settings.RAW_SENSOR_WINDOWS_CACHE_TTL_SECONDS
    if ttl <= 0:
        return
    try:
        _get_redis_client().setex(_cache_key(upload_id), ttl, pickle.dumps(windows))
    except RedisError:
        return
