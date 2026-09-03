"""Cache Redis del risultato di lettura raw sensor di una TripUpload.

`process_trip_har_final` accoda `persist_trip_raw_sensor_readings` per la
stessa upload (vedi `tasks.py`): i due task, in due processi Celery
separati, chiamano entrambi `load_raw_sensor_windows_with_metrics` per lo
stesso `upload_id`, riscaricando e ridecodificando lo stesso payload da
object storage. TTL breve (non cancellazione esplicita a fine task): il
secondo consumatore arriva tipicamente entro pochi secondi dal primo, ma il
TTL copre anche un eventuale retry di `persist_trip_raw_sensor_readings`
(max_retries=3, retry_backoff) senza dover ripetere il lavoro.
"""

from __future__ import annotations

import pickle
from typing import TYPE_CHECKING

from django.conf import settings
from redis import Redis
from redis.exceptions import RedisError

if TYPE_CHECKING:
    from .upload.raw_sensor_loader import RawSensorLoadResult


def _cache_key(upload_id: int) -> str:
    return f"raw_sensor_windows:{upload_id}"


def _get_redis_client() -> Redis:
    return Redis.from_url(settings.REDIS_URL, decode_responses=False)


def get_cached_raw_sensor_windows(upload_id: int) -> "RawSensorLoadResult | None":
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
        # Una entry scritta da una versione precedente del codice puo'
        # riferirsi a un modulo o a una classe che nel frattempo sono
        # stati rinominati (ModuleNotFoundError/AttributeError): la
        # cache deve degradare a miss, mai far fallire il chiamante.
        return None


def cache_raw_sensor_windows(
    upload_id: int, result: "RawSensorLoadResult"
) -> None:
    if not result.windows:
        return
    ttl = settings.RAW_SENSOR_WINDOWS_CACHE_TTL_SECONDS
    if ttl <= 0:
        return
    try:
        _get_redis_client().setex(_cache_key(upload_id), ttl, pickle.dumps(result))
    except RedisError:
        return
