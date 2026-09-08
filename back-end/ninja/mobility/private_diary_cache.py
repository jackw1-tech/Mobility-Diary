"""Cache Redis del diario privato di un Trip.
"""

from __future__ import annotations

import pickle
from typing import TYPE_CHECKING

from django.conf import settings
from redis import Redis
from redis.exceptions import RedisError

if TYPE_CHECKING:
    from .services.diary_view import DiarySegmentView


def _get_redis_client() -> Redis:
    return Redis.from_url(settings.REDIS_URL, decode_responses=False)


def _places_version_key(user_id: int) -> str:
    return f"places_version:{user_id}"

# Restituisce la chiave dell'ultimo aggiornamento dei luoghi significativi
def get_places_version(user_id: int) -> int:
    try:
        raw = _get_redis_client().get(_places_version_key(user_id))
    except RedisError:
        return 0
    if raw is None:
        return 0
    try:
        return int(raw)
    except (TypeError, ValueError):
        return 0


def bump_places_version(user_id: int) -> None:
    try:
        _get_redis_client().incr(_places_version_key(user_id))
    except RedisError:
        return

#Costruisce la chiave
def _diary_cache_key(trip_id: int, places_version: int) -> str:
    return f"private_diary:{trip_id}:{places_version}"

#Cerco nella cache il diario
def get_cached_diary(
    trip_id: int, places_version: int
) -> "list[DiarySegmentView] | None":
    try:
        raw = _get_redis_client().get(_diary_cache_key(trip_id, places_version))
    except RedisError:
        return None
    if raw is None:
        return None
    try:
        return pickle.loads(raw) #Byte -> Oggetto Python
    except (pickle.PickleError, EOFError, TypeError, ValueError):
        return None

# Inserisco in cache il diario
def cache_diary(
    trip_id: int,
    places_version: int,
    diary: "list[DiarySegmentView]",
) -> None:
    ttl = settings.PRIVATE_DIARY_CACHE_TTL_SECONDS
    if ttl <= 0:
        return
    try:
        _get_redis_client().setex(
            _diary_cache_key(trip_id, places_version), ttl, pickle.dumps(diary) #Oggetto python -> Byte
        )
    except RedisError:
        return
