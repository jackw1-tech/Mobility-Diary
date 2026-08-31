"""Cache Redis del diario privato (`build_private_diary`) di un Trip.

Il calcolo (GPS grezzi del viaggio + matching con i Luoghi Confermati
dell'utente) e' a tempo di lettura per costruzione: un Luogo Confermato/
Rifiutato/Rietichettato dopo la fine del viaggio deve riflettersi sui diari
gia' visualizzati. Non si puo' pero' sapere a buon mercato QUALI viaggi
passati tocchi una modifica ai luoghi (il matching e' geometrico, non una
relazione salvata) — invalidare "a generazione" risolve senza doverlo sapere:

- ogni utente ha un contatore `places_version` in Redis;
- la chiave di cache di un diario include la versione corrente;
- confermare/rifiutare/rietichettare un luogo fa solo un INCR (O(1), nessuna
  query): la versione cambia, tutte le chiavi vecchie diventano irraggiungibili
  per costruzione (chiave diversa), senza dover enumerare o cancellare nulla.

TTL lungo (default una settimana): non e' il meccanismo di invalidazione
(lo e' il contatore), serve solo a liberare le entry ormai orfane.
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


def _diary_cache_key(trip_id: int, places_version: int) -> str:
    return f"private_diary:{trip_id}:{places_version}"


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
        return pickle.loads(raw)
    except (pickle.PickleError, EOFError, TypeError, ValueError):
        return None


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
            _diary_cache_key(trip_id, places_version), ttl, pickle.dumps(diary)
        )
    except RedisError:
        return
