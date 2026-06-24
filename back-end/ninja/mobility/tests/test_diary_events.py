import json

from mobility.diary_events import (
    DIARY_STATUS_ENRICHED,
    diary_status_channel,
    diary_status_payload,
    encode_diary_status_payload,
    publish_diary_status,
)


class FakeRedis:
    def __init__(self):
        self.published = []

    def publish(self, channel, message):
        self.published.append((channel, message))


def test_diary_status_channel_and_payload_are_canonical():
    payload = diary_status_payload(42, DIARY_STATUS_ENRICHED)

    assert diary_status_channel(42) == "diary_status:42"
    assert payload == {"trip_id": 42, "status": "enriched"}
    assert encode_diary_status_payload(payload) == '{"trip_id":42,"status":"enriched"}'


def test_publish_diary_status_uses_canonical_channel_and_payload():
    redis_client = FakeRedis()
    expected = json.dumps(
        {"trip_id": 42, "status": "enriched"},
        separators=(",", ":"),
    )

    publish_diary_status(42, DIARY_STATUS_ENRICHED, redis_client=redis_client)

    assert redis_client.published == [("diary_status:42", expected)]
