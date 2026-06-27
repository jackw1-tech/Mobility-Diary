import asyncio
from datetime import timedelta

import pytest
from asgiref.sync import async_to_sync
from django.contrib.auth import get_user_model
from django.contrib.gis.geos import LineString, Point
from django.test import Client
from django.utils import timezone

from accounts.models import AccessToken
from mobility import api as mobility_api
from mobility.models import (
    ActivityLabel,
    GpsPoint,
    MobilitySegment,
    PartKind,
    SignificantPlace,
    StateTransition,
    Trip,
    TripIngestion,
    TripIngestionPart,
)
from mobility.tasks import _build_trip_path, process_trip_ingestion


@pytest.fixture
def user(db):
    return get_user_model().objects.create_user(
        username="owner@example.com",
        email="owner@example.com",
        password="password",
    )


@pytest.fixture
def other_user(db):
    return get_user_model().objects.create_user(
        username="other@example.com",
        email="other@example.com",
        password="password",
    )


def auth_headers(user):
    raw_token, _ = AccessToken.issue_for_user(user)
    return {"HTTP_AUTHORIZATION": f"Bearer {raw_token}"}


def create_trip(user, *, client_session_id="session-track") -> Trip:
    return Trip.objects.create(
        user=user,
        client_session_id=client_session_id,
        device_id="test-device",
        status=Trip.Status.CLOSED,
    )


def add_gps(trip: Trip, timestamp, lon: float, lat: float) -> GpsPoint:
    return GpsPoint.objects.create(
        trip=trip,
        timestamp=timestamp,
        point=Point(lon, lat, srid=4326),
        speed_mps=1.0,
    )


@pytest.mark.django_db
def test_build_trip_path_orders_points_by_timestamp(user):
    trip = create_trip(user)
    base = timezone.now()
    add_gps(trip, base + timedelta(minutes=2), 9.30, 45.46)
    add_gps(trip, base, 9.10, 45.46)
    add_gps(trip, base + timedelta(minutes=1), 9.20, 45.46)

    point_count = _build_trip_path(trip)

    trip.refresh_from_db()
    assert point_count == 3
    assert trip.path is not None
    assert trip.distance_meters > 0
    assert list(trip.path.coords) == [
        (9.10, 45.46),
        (9.20, 45.46),
        (9.30, 45.46),
    ]


@pytest.mark.django_db
@pytest.mark.parametrize("point_count", [0, 1])
def test_build_trip_path_keeps_path_empty_for_less_than_two_points(user, point_count):
    trip = create_trip(user, client_session_id=f"empty-{point_count}")
    if point_count:
        add_gps(trip, timezone.now(), 9.19, 45.46)

    returned_count = _build_trip_path(trip)

    trip.refresh_from_db()
    assert returned_count == point_count
    assert trip.path is None
    assert trip.distance_meters == 0


@pytest.mark.django_db
def test_process_trip_ingestion_builds_path_idempotently(monkeypatch, user):
    ingestion = TripIngestion.objects.create(
        user=user,
        client_session_id="ingestion-track",
        device_id="test-device",
        expected_core_parts={"gps_points": 1, "state_transitions": 1},
        expected_raw_parts={},
        raw_status=TripIngestion.PhaseStatus.COMPLETED,
    )
    now = timezone.now()
    TripIngestionPart.objects.create(
        ingestion=ingestion,
        kind=PartKind.GPS_POINTS,
        sequence=1,
        sha256="gps",
        object_key="gps.json.gz",
        received_at=now,
    )
    TripIngestionPart.objects.create(
        ingestion=ingestion,
        kind=PartKind.STATE_TRANSITIONS,
        sequence=1,
        sha256="state",
        object_key="state.json.gz",
        received_at=now,
    )

    def fake_load_json_gz(object_key):
        if object_key == "gps.json.gz":
            return {
                "points": [
                    {
                        "timestamp": (now + timedelta(minutes=2)).isoformat(),
                        "latitude": 45.46,
                        "longitude": 9.30,
                        "speed_mps": 1.0,
                    },
                    {
                        "timestamp": now.isoformat(),
                        "latitude": 45.46,
                        "longitude": 9.10,
                        "speed_mps": 1.0,
                    },
                ]
            }
        return {
            "transitions": [
                {
                    "timestamp": now.isoformat(),
                    "from_state": "STATIONARY",
                    "to_state": "ACTIVE_TRACKING",
                    "reason": "test",
                }
            ]
        }

    monkeypatch.setattr("mobility.tasks._load_json_gz", fake_load_json_gz)

    first_result = process_trip_ingestion.run(ingestion.id)
    second_result = process_trip_ingestion.run(ingestion.id)

    trip = Trip.objects.get(client_session_id="ingestion-track")
    assert first_result["path_points"] == 2
    assert second_result == {"skipped": "core ingestion already completed"}
    assert GpsPoint.objects.filter(trip=trip).count() == 2
    assert StateTransition.objects.filter(trip=trip).count() == 1
    assert trip.path is not None
    assert list(trip.path.coords) == [(9.10, 45.46), (9.30, 45.46)]


@pytest.mark.django_db
def test_track_endpoint_returns_geojson_distance_and_lon_lat_order(user):
    trip = create_trip(user)
    base = timezone.now()
    add_gps(trip, base, 9.10, 45.46)
    add_gps(trip, base + timedelta(minutes=1), 9.20, 45.47)
    _build_trip_path(trip)
    trip.refresh_from_db()

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/track",
        **auth_headers(user),
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["trip_id"] == trip.id
    assert payload["point_count"] == 2
    assert payload["distance_meters"] > 0
    assert payload["geojson"]["type"] == "LineString"
    assert payload["geojson"]["coordinates"][0] == [9.10, 45.46]
    assert payload["geojson"]["coordinates"][1] == [9.20, 45.47]


@pytest.mark.django_db
def test_track_endpoint_returns_404_for_other_user(user, other_user):
    trip = create_trip(user)
    add_gps(trip, timezone.now(), 9.10, 45.46)

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/track",
        **auth_headers(other_user),
    )

    assert response.status_code == 404


@pytest.mark.django_db
def test_track_endpoint_returns_empty_track_for_trip_without_path(user):
    trip = create_trip(user)
    add_gps(trip, timezone.now(), 9.10, 45.46)

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/track",
        **auth_headers(user),
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["trip_id"] == trip.id
    assert payload["point_count"] == 1
    assert payload["distance_meters"] == 0
    assert payload["geojson"] is None


@pytest.mark.django_db
def test_diary_endpoint_returns_not_yet_enriched_state(user):
    trip = create_trip(user)

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/diary",
        **auth_headers(user),
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["trip_id"] == trip.id
    assert payload["status"] == Trip.Status.CLOSED
    assert payload["processed"] is False
    assert payload["segments"] == []
    assert payload["places"] == []


@pytest.mark.django_db
def test_diary_endpoint_returns_segment_geometry_and_stop_place(user, other_user):
    trip = create_trip(user)
    trip.status = Trip.Status.PROCESSED
    trip.save(update_fields=["status", "updated_at"])
    base = timezone.now()
    place = SignificantPlace.objects.create(
        trip=trip,
        center=Point(9.20, 45.47, srid=4326),
        radius_meters=45,
        dwell_seconds=600,
        label="universita",
    )
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.MOVE,
        start_timestamp=base,
        end_timestamp=base + timedelta(minutes=10),
        activity_label=ActivityLabel.BIKING,
        path=LineString((9.10, 45.46), (9.20, 45.47), srid=4326),
        distance_meters=1200,
    )
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.STOP,
        start_timestamp=base + timedelta(minutes=10),
        end_timestamp=base + timedelta(minutes=20),
        activity_label=ActivityLabel.IDLE,
        place=place,
    )

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/diary",
        **auth_headers(user),
    )
    other_response = Client().get(
        f"/api/mobility/trips/{trip.id}/diary",
        **auth_headers(other_user),
    )

    assert response.status_code == 200
    assert other_response.status_code == 404
    payload = response.json()
    assert payload["processed"] is True
    assert len(payload["segments"]) == 2
    move, stop = payload["segments"]
    assert move["kind"] == MobilitySegment.Kind.MOVE
    assert move["activity_label"] == ActivityLabel.BIKING
    assert move["path_geojson"]["type"] == "LineString"
    assert move["path_geojson"]["coordinates"] == [[9.1, 45.46], [9.2, 45.47]]
    assert stop["kind"] == MobilitySegment.Kind.STOP
    assert stop["path_geojson"] is None
    assert stop["place"]["label"] == "universita"


@pytest.mark.django_db
def test_diary_endpoint_merges_consecutive_stop_and_idle_move(user):
    trip = create_trip(user)
    trip.status = Trip.Status.PROCESSED
    trip.save(update_fields=["status", "updated_at"])
    base = timezone.now()
    place = SignificantPlace.objects.create(
        trip=trip,
        center=Point(9.20, 45.47, srid=4326),
        radius_meters=45,
        dwell_seconds=600,
        label="universita",
    )
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.STOP,
        start_timestamp=base,
        end_timestamp=base + timedelta(minutes=5),
        activity_label=ActivityLabel.IDLE,
        place=place,
    )
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.MOVE,
        start_timestamp=base + timedelta(minutes=5),
        end_timestamp=base + timedelta(minutes=10),
        activity_label=ActivityLabel.IDLE,
        path=LineString((9.20, 45.47), (9.2001, 45.4701), srid=4326),
        distance_meters=30,
    )

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/diary",
        **auth_headers(user),
    )

    assert response.status_code == 200
    payload = response.json()
    assert len(payload["segments"]) == 1
    stop = payload["segments"][0]
    assert stop["kind"] == MobilitySegment.Kind.STOP
    assert stop["activity_label"] == ActivityLabel.IDLE
    assert stop["path_geojson"] is None
    assert stop["distance_meters"] == 0
    assert stop["place"]["label"] == "universita"


def _read_streaming_body(response) -> str:
    """Consuma il body async di una StreamingHttpResponse da un test sincrono."""

    async def _collect():
        parts = []
        async for part in response.streaming_content:
            parts.append(part)
        return b"".join(parts)

    return async_to_sync(_collect)().decode("utf-8")


class _FakePubSub:
    def __init__(self, messages=None):
        self.messages = list(messages or [])
        self.subscribed = []
        self.unsubscribed = []
        self.listen_called = False
        self.closed = False

    async def subscribe(self, channel):
        self.subscribed.append(channel)

    async def unsubscribe(self, channel):
        self.unsubscribed.append(channel)

    async def aclose(self):
        self.closed = True

    async def listen(self):
        self.listen_called = True
        yield {"type": "subscribe"}
        for data in self.messages:
            yield {"type": "message", "data": data}
        while True:
            await asyncio.sleep(3600)


class _FakeRedis:
    def __init__(self, pubsub):
        self._pubsub = pubsub
        self.closed = False

    def pubsub(self):
        return self._pubsub

    async def aclose(self):
        self.closed = True


def _install_fake_diary_redis(monkeypatch, *, messages=None):
    pubsub = _FakePubSub(messages)
    client = _FakeRedis(pubsub)
    monkeypatch.setattr(mobility_api, "create_async_redis_client", lambda: client)
    return pubsub, client


@pytest.mark.django_db
def test_trip_events_emits_enriched_diary_status_for_processed_trip(
    user,
    monkeypatch,
):
    trip = create_trip(user)
    trip.status = Trip.Status.PROCESSED
    trip.save(update_fields=["status", "updated_at"])
    _install_fake_diary_redis(monkeypatch)

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/events",
        **auth_headers(user),
    )

    assert response.status_code == 200
    assert response["Content-Type"].startswith("text/event-stream")
    body = _read_streaming_body(response)
    assert "event: diary_status" in body
    assert f'"trip_id":{trip.id}' in body
    assert '"status":"enriched"' in body


@pytest.mark.django_db
def test_trip_events_emits_failed_diary_status_for_final_ingestion_failure(
    user,
    monkeypatch,
):
    trip = create_trip(user)
    TripIngestion.objects.create(
        user=user,
        trip=trip,
        client_session_id="failed-raw",
        raw_status=TripIngestion.PhaseStatus.FAILED_FINAL,
    )
    _install_fake_diary_redis(monkeypatch)

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/events",
        **auth_headers(user),
    )

    assert response.status_code == 200
    body = _read_streaming_body(response)
    assert "event: diary_status" in body
    assert f'"trip_id":{trip.id}' in body
    assert '"status":"failed"' in body
    assert '"reason":"diary_enrichment_failed"' in body


@pytest.mark.django_db
def test_trip_events_returns_404_for_other_user(user, other_user):
    trip = create_trip(user)

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/events",
        **auth_headers(other_user),
    )

    assert response.status_code == 404


@pytest.mark.django_db
def test_trip_diary_failure_reason_ignores_retryable_ingestion(user):
    trip = create_trip(user)
    TripIngestion.objects.create(
        user=user,
        trip=trip,
        client_session_id="retryable-raw",
        raw_status=TripIngestion.PhaseStatus.FAILED_RETRYABLE,
    )

    reason = async_to_sync(mobility_api._trip_diary_failure_reason)(
        trip.id,
        user.id,
    )

    assert reason is None


def test_trip_event_stream_emits_current_status_after_subscribe(monkeypatch):
    pubsub, _client = _install_fake_diary_redis(monkeypatch)

    async def fake_current_status(trip_id, user_id):
        assert pubsub.subscribed == ["diary_status:7"]
        return {"trip_id": trip_id, "status": "enriched"}

    monkeypatch.setattr(
        mobility_api,
        "_trip_diary_status_payload",
        fake_current_status,
    )

    async def collect():
        stream = mobility_api._trip_diary_event_stream(
            7,
            11,
            max_seconds=10,
        )
        return [chunk async for chunk in stream]

    results = async_to_sync(collect)()

    assert results == [
        'event: diary_status\ndata: {"trip_id":7,"status":"enriched"}\n\n',
    ]
    assert pubsub.listen_called is False
    assert pubsub.unsubscribed == ["diary_status:7"]


def test_trip_event_stream_emits_published_diary_status(monkeypatch):
    _install_fake_diary_redis(
        monkeypatch,
        messages=[
            (
                '{"trip_id":7,"status":"failed",'
                '"reason":"diary_enrichment_failed"}'
            ),
        ],
    )

    async def fake_current_status(trip_id, user_id):
        return None

    monkeypatch.setattr(
        mobility_api,
        "_trip_diary_status_payload",
        fake_current_status,
    )

    async def collect():
        stream = mobility_api._trip_diary_event_stream(
            7,
            11,
            max_seconds=10,
        )
        return [chunk async for chunk in stream]

    results = async_to_sync(collect)()

    assert results == [
        (
            'event: diary_status\n'
            'data: {"trip_id":7,"status":"failed",'
            '"reason":"diary_enrichment_failed"}\n\n'
        ),
    ]


def test_trip_event_stream_times_out_without_diary_status(monkeypatch):
    _install_fake_diary_redis(monkeypatch)

    async def fake_current_status(trip_id, user_id):
        return None

    monkeypatch.setattr(
        mobility_api,
        "_trip_diary_status_payload",
        fake_current_status,
    )

    async def collect():
        stream = mobility_api._trip_diary_event_stream(
            7,
            11,
            max_seconds=0.01,
        )
        return [chunk async for chunk in stream]

    results = async_to_sync(collect)()

    assert results == [": timeout\n\n"]
