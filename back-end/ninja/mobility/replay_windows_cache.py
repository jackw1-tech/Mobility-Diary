"""Cache Redis delle finestre sensore decodificate di un viaggio sorgente.
"""

from __future__ import annotations

import pickle

from django.conf import settings
from redis import Redis
from redis.exceptions import RedisError

from .ml.pipeline import PipelineSensorWindow


def _cache_key(trip_id: int) -> str:
    return f"replay_windows:{trip_id}"


def _get_redis_client() -> Redis:
    return Redis.from_url(settings.REDIS_URL, decode_responses=False)


def get_cached_windows(trip_id: int) -> list[PipelineSensorWindow] | None:
    try:
        raw = _get_redis_client().get(_cache_key(trip_id))
    except RedisError:
        return None
    if raw is None:
        return None
    try:
        return pickle.loads(raw)
    except (pickle.PickleError, EOFError, TypeError, ValueError,
            ImportError, AttributeError):
        return None

""" 
Nel momento in cui sono in modalità replay live e voglio classificare un viaggio
la prima chiamata di classificazione scarica tutti i raw parts, li decodifica e li mette in cache
Le chiamate successive (tick di 15 secondi) non devono riscaricarle ma leggono il dato in cache
TTL di 1 ora
"""
def cache_windows(trip_id: int, windows: list[PipelineSensorWindow]) -> None:
    if not windows:
        return
    ttl = settings.REPLAY_WINDOWS_CACHE_TTL_SECONDS
    if ttl <= 0:
        return
    try:
        _get_redis_client().setex(_cache_key(trip_id), ttl, pickle.dumps(windows))
    except RedisError:
        return
