import json

from django.conf import settings
from django.db import transaction
from redis import Redis
from redis.asyncio import Redis as AsyncRedis

DIARY_STATUS_EVENT = "diary_status"
DIARY_STATUS_ENRICHED = "enriched"
DIARY_STATUS_FAILED = "failed"
DIARY_ENRICHMENT_FAILED_REASON = "diary_enrichment_failed"


def diary_status_channel(trip_id: int) -> str:
    return f"diary_status:{trip_id}"


def diary_status_payload(
    trip_id: int,
    status: str,
    *,
    reason: str | None = None,
) -> dict:
    payload = {"trip_id": trip_id, "status": status}
    if reason is not None:
        payload["reason"] = reason
    return payload


def encode_diary_status_payload(payload: dict) -> str:
    return json.dumps(payload, separators=(",", ":"))


def publish_diary_status(
    trip_id: int,
    status: str,
    *,
    reason: str | None = None,
    redis_client: Redis | None = None,
) -> None:
    owns_client = redis_client is None
    client = redis_client or Redis.from_url(
        settings.REDIS_URL,
        decode_responses=True,
    )
    try:
        client.publish(
            diary_status_channel(trip_id),
            encode_diary_status_payload(
                diary_status_payload(trip_id, status, reason=reason)
            ),
        )
    finally:
        if owns_client:
            client.close()


def publish_diary_status_on_commit(
    trip_id: int,
    status: str,
    *,
    reason: str | None = None,
) -> None:
    transaction.on_commit(
        lambda: publish_diary_status(trip_id, status, reason=reason),
        robust=True,
    )


def create_async_redis_client() -> AsyncRedis:
    return AsyncRedis.from_url(settings.REDIS_URL, decode_responses=True)
