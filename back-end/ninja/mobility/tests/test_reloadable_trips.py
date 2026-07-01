import gzip
import hashlib
import json
from datetime import datetime, timedelta, timezone as dt_timezone

import pytest
from django.contrib.auth import get_user_model
from django.contrib.gis.geos import Point
from django.test import Client
from django.utils import timezone

from accounts.models import AccessToken
from mobility.models import (
    GpsPoint,
    HarJob,
    PartKind,
    StateTransition,
    Trip,
    TripIngestion,
    TripIngestionPart,
)
from mobility.tasks import _build_trip_path, process_trip_har_final


@pytest.fixture
def user(db):
    return get_user_model().objects.create_user(
        username="reloader@example.com",
        email="reloader@example.com",
        password="password",
    )


@pytest.fixture
def source_owner(user):
    return user


@pytest.fixture
def other_source_owner(db):
    return get_user_model().objects.create_user(
        username="source-owner@example.com",
        email="source-owner@example.com",
        password="password",
    )


def auth_headers(user):
    raw_token, _ = AccessToken.issue_for_user(user)
    return {"HTTP_AUTHORIZATION": f"Bearer {raw_token}"}


@pytest.fixture
def object_storage(monkeypatch):
    objects: dict[str, bytes] = {}
    monkeypatch.setattr("mobility.replay_raw.storage.read_object", objects.__getitem__)
    monkeypatch.setattr(
        "mobility.replay_raw.storage.write_object",
        lambda key, body, **_kwargs: objects.__setitem__(key, body),
    )
    monkeypatch.setattr(
        "mobility.replay_raw.storage.delete_object",
        lambda key: objects.pop(key, None),
    )
    return objects


@pytest.fixture
def har_delays(monkeypatch):
    delayed: list[tuple[int, int]] = []
    monkeypatch.setattr(
        process_trip_har_final,
        "delay",
        lambda job_id, ingestion_id: delayed.append((job_id, ingestion_id)),
    )
    return delayed


def gzipped(data: dict) -> bytes:
    return gzip.compress(json.dumps(data).encode("utf-8"))


def make_reloadable_trip(owner, *, source_start: timezone.datetime) -> Trip:
    trip = Trip.objects.create(
        user=owner,
        client_session_id="source-session",
        device_id="source-device",
        status=Trip.Status.CLOSED,
        is_reloadable=True,
        ended_at=source_start + timedelta(minutes=20),
    )
    Trip.objects.filter(pk=trip.pk).update(started_at=source_start)
    trip.refresh_from_db()
    GpsPoint.objects.create(
        trip=trip,
        timestamp=source_start,
        point=Point(9.10, 45.40, srid=4326),
        speed_mps=1.0,
        accuracy_meters=7.0,
    )
    GpsPoint.objects.create(
        trip=trip,
        timestamp=source_start + timedelta(minutes=20),
        point=Point(9.20, 45.50, srid=4326),
        speed_mps=2.0,
        accuracy_meters=8.0,
    )
    StateTransition.objects.create(
        trip=trip,
        timestamp=source_start + timedelta(minutes=5),
        from_state="STATIONARY",
        to_state="MOVEMENT",
        reason="source",
        sigma=1.2,
        speed_mps=1.5,
    )
    _build_trip_path(trip)
    return trip


def add_raw_sensor_part(
    trip: Trip,
    objects: dict[str, bytes],
    *,
    source_start,
    sequence: int = 1,
    minute: int = 1,
):
    body = {
        "windows": [
            {
                "window_start": (
                    source_start + timedelta(minutes=minute)
                ).isoformat().replace("+00:00", "Z"),
                "window_end": (
                    source_start + timedelta(minutes=minute, seconds=5)
                ).isoformat().replace("+00:00", "Z"),
                "sample_rate_hz": 100,
                "sample_count": 2,
                "samples": [[1, 2, 3, 4, 5, 6], [7, 8, 9, 10, 11, 12]],
            }
        ]
    }
    object_key = f"source/{trip.id}/sensor_windows_{sequence:04d}.json.gz"
    raw = gzipped(body)
    objects[object_key] = raw
    ingestion = TripIngestion.objects.create(
        user=trip.user,
        client_session_id=f"source-ingestion-{trip.id}-{sequence}",
        device_id=trip.device_id,
        core_status=TripIngestion.PhaseStatus.COMPLETED,
        raw_status=TripIngestion.PhaseStatus.COMPLETED,
        trip=trip,
    )
    TripIngestionPart.objects.create(
        ingestion=ingestion,
        kind=PartKind.SENSOR_WINDOWS,
        sequence=sequence,
        sha256=hashlib.sha256(raw).hexdigest(),
        size_bytes=len(raw),
        object_key=object_key,
        received_at=timezone.now(),
    )
    return object_key, body


def post_reload(client, user, trip, *, reload_request_id, scheduled_start_at=None):
    body = {"reload_request_id": reload_request_id}
    if scheduled_start_at is not None:
        body["scheduled_start_at"] = scheduled_start_at.isoformat()
    return client.post(
        f"/api/mobility/trips/reloadable/{trip.id}/reload",
        data=json.dumps(body),
        content_type="application/json",
        **auth_headers(user),
    )


def reload_client_session_id(user, trip, request_id: str) -> str:
    key = f"{user.id}:{trip.id}:{request_id}".encode("utf-8")
    return f"reload-{hashlib.sha256(key).hexdigest()[:57]}"


@pytest.mark.django_db
def test_reload_slots_return_past_non_overlapping_candidates(
    user, source_owner, monkeypatch, object_storage
):
    now = datetime(2026, 6, 30, 15, tzinfo=dt_timezone.utc)
    source_start = datetime(2026, 6, 12, 10, tzinfo=dt_timezone.utc)
    source = make_reloadable_trip(source_owner, source_start=source_start)
    add_raw_sensor_part(source, object_storage, source_start=source_start)
    Trip.objects.create(
        user=user,
        device_id="existing",
        status=Trip.Status.CLOSED,
        started_at=now - timedelta(hours=1),
        ended_at=now - timedelta(minutes=30),
    )
    monkeypatch.setattr("mobility.api.timezone.now", lambda: now)

    response = Client().get(
        f"/api/mobility/trips/reloadable/{source.id}/slots",
        {"days": 1, "step_minutes": 15},
        **auth_headers(user),
    )

    assert response.status_code == 200, response.content
    data = response.json()
    assert data["source_trip_id"] == source.id
    assert data["duration_seconds"] == 20 * 60
    slots = [
        (
            datetime.fromisoformat(slot["started_at"]),
            datetime.fromisoformat(slot["ended_at"]),
        )
        for slot in data["slots"]
    ]
    assert slots
    assert slots == sorted(slots, reverse=True)
    assert all(start < end <= now for start, end in slots)
    assert all(
        end <= now - timedelta(hours=1) or start >= now - timedelta(minutes=30)
        for start, end in slots
    )


@pytest.mark.django_db
def test_direct_reload_uses_selected_past_start(
    user, source_owner, monkeypatch, object_storage, har_delays
):
    source_start = datetime(2026, 6, 12, 10, tzinfo=dt_timezone.utc)
    selected_start = datetime(2026, 6, 29, 12, 15, tzinfo=dt_timezone.utc)
    source = make_reloadable_trip(source_owner, source_start=source_start)
    add_raw_sensor_part(source, object_storage, source_start=source_start)
    monkeypatch.setattr(
        "mobility.api.timezone.now",
        lambda: datetime(2026, 6, 30, 15, tzinfo=dt_timezone.utc),
    )

    response = post_reload(
        Client(),
        user,
        source,
        reload_request_id="selected-start",
        scheduled_start_at=selected_start,
    )

    assert response.status_code == 200, response.content
    reloaded = Trip.objects.get(id=response.json()["trip_id"])
    assert reloaded.started_at == selected_start
    assert reloaded.ended_at == selected_start + timedelta(minutes=20)


@pytest.mark.django_db
def test_direct_reload_rejects_selected_start_that_overlaps_or_ends_in_future(
    user, source_owner, monkeypatch, object_storage, har_delays
):
    now = datetime(2026, 6, 30, 15, tzinfo=dt_timezone.utc)
    source_start = datetime(2026, 6, 12, 10, tzinfo=dt_timezone.utc)
    source = make_reloadable_trip(source_owner, source_start=source_start)
    add_raw_sensor_part(source, object_storage, source_start=source_start)
    Trip.objects.create(
        user=user,
        device_id="existing",
        status=Trip.Status.CLOSED,
        started_at=now - timedelta(hours=1),
        ended_at=now - timedelta(minutes=30),
    )
    monkeypatch.setattr("mobility.api.timezone.now", lambda: now)

    overlap = post_reload(
        Client(),
        user,
        source,
        reload_request_id="overlap",
        scheduled_start_at=now - timedelta(minutes=45),
    )
    future = post_reload(
        Client(),
        user,
        source,
        reload_request_id="future",
        scheduled_start_at=now - timedelta(minutes=10),
    )

    assert overlap.status_code == 409
    assert future.status_code == 409
    assert not Trip.objects.filter(user=user, reloaded_from_trip=source).exists()


@pytest.mark.django_db
def test_direct_reload_creates_new_stop_like_trip_for_clicking_user(
    user, source_owner, monkeypatch, object_storage, har_delays
):
    source_start = datetime(2026, 6, 12, 10, tzinfo=dt_timezone.utc)
    reload_now = datetime(2026, 6, 30, 15, tzinfo=dt_timezone.utc)
    source = make_reloadable_trip(source_owner, source_start=source_start)
    add_raw_sensor_part(source, object_storage, source_start=source_start)
    monkeypatch.setattr("mobility.api.timezone.now", lambda: reload_now)

    response = post_reload(
        Client(),
        user,
        source,
        reload_request_id="reload-request-1",
    )

    assert response.status_code == 200, response.content
    data = response.json()
    reloaded = Trip.objects.get(id=data["trip_id"])
    ingestion = TripIngestion.objects.get(id=data["ingestion_id"])

    assert reloaded.id != source.id
    assert reloaded.user_id == user.id
    assert reloaded.reloaded_from_trip_id == source.id
    assert reloaded.started_at == reload_now - timedelta(minutes=20)
    assert reloaded.ended_at == reload_now
    assert ingestion.trip_id == reloaded.id
    assert ingestion.core_status == TripIngestion.PhaseStatus.COMPLETED
    assert data["raw_status"] == TripIngestion.PhaseStatus.QUEUED
    assert data["map_available"] is True

    reloaded_points = list(reloaded.gps_points.order_by("timestamp"))
    assert [point.timestamp for point in reloaded_points] == [
        reload_now - timedelta(minutes=20),
        reload_now,
    ]
    assert [(point.longitude, point.latitude) for point in reloaded_points] == [
        (9.10, 45.40),
        (9.20, 45.50),
    ]
    assert list(
        reloaded.state_transitions.values_list("timestamp", "reason")
    ) == [(reload_now - timedelta(minutes=15), "source")]


@pytest.mark.django_db
def test_direct_reload_does_not_copy_source_note(
    user, source_owner, monkeypatch, object_storage, har_delays
):
    source_start = datetime(2026, 6, 12, 10, tzinfo=dt_timezone.utc)
    source = make_reloadable_trip(source_owner, source_start=source_start)
    Trip.objects.filter(pk=source.pk).update(note="Nota privata")
    add_raw_sensor_part(source, object_storage, source_start=source_start)
    monkeypatch.setattr(
        "mobility.api.timezone.now",
        lambda: datetime(2026, 6, 30, 15, tzinfo=dt_timezone.utc),
    )

    response = post_reload(Client(), user, source, reload_request_id="no-note-copy")

    assert response.status_code == 200, response.content
    assert Trip.objects.get(id=response.json()["trip_id"]).note == ""


@pytest.mark.django_db
def test_direct_reload_is_idempotent_per_reload_request_id(
    user, source_owner, monkeypatch, object_storage, har_delays
):
    source_start = datetime(2026, 6, 12, 10, tzinfo=dt_timezone.utc)
    source = make_reloadable_trip(
        source_owner,
        source_start=source_start,
    )
    add_raw_sensor_part(source, object_storage, source_start=source_start)
    monkeypatch.setattr(
        "mobility.api.timezone.now",
        lambda: datetime(2026, 6, 30, 15, tzinfo=dt_timezone.utc),
    )

    first = post_reload(Client(), user, source, reload_request_id="same-request")
    second = post_reload(Client(), user, source, reload_request_id="same-request")
    third = post_reload(Client(), user, source, reload_request_id="new-request")

    assert first.status_code == 200, first.content
    assert second.status_code == 200, second.content
    assert third.status_code == 200, third.content
    assert second.json()["trip_id"] == first.json()["trip_id"]
    assert third.json()["trip_id"] != first.json()["trip_id"]
    assert Trip.objects.filter(user=user, reloaded_from_trip=source).count() == 2


@pytest.mark.django_db
def test_direct_reload_preserves_source_trip_duration_beyond_last_evidence(
    user, source_owner, monkeypatch, object_storage, har_delays
):
    source_start = datetime(2026, 6, 12, 10, tzinfo=dt_timezone.utc)
    reload_now = datetime(2026, 6, 30, 15, tzinfo=dt_timezone.utc)
    source = make_reloadable_trip(source_owner, source_start=source_start)
    Trip.objects.filter(pk=source.pk).update(
        ended_at=source_start + timedelta(minutes=25),
    )
    source.refresh_from_db()
    add_raw_sensor_part(source, object_storage, source_start=source_start)
    monkeypatch.setattr("mobility.api.timezone.now", lambda: reload_now)

    response = post_reload(Client(), user, source, reload_request_id="duration")

    assert response.status_code == 200, response.content
    reloaded = Trip.objects.get(id=response.json()["trip_id"])
    assert reloaded.started_at == reload_now - timedelta(minutes=25)
    assert reloaded.ended_at == reload_now
    timestamps = list(
        reloaded.gps_points.order_by("timestamp").values_list("timestamp", flat=True)
    )
    assert timestamps == [
        reload_now - timedelta(minutes=25),
        reload_now - timedelta(minutes=5),
    ]


@pytest.mark.django_db
def test_direct_reload_retry_recovers_incomplete_same_request(
    user, source_owner, monkeypatch, object_storage, har_delays
):
    source_start = datetime(2026, 6, 12, 10, tzinfo=dt_timezone.utc)
    source = make_reloadable_trip(source_owner, source_start=source_start)
    add_raw_sensor_part(source, object_storage, source_start=source_start)
    request_id = "recover-incomplete"
    TripIngestion.objects.create(
        user=user,
        client_session_id=reload_client_session_id(user, source, request_id),
        device_id="reload",
    )
    monkeypatch.setattr(
        "mobility.api.timezone.now",
        lambda: datetime(2026, 6, 30, 15, tzinfo=dt_timezone.utc),
    )

    response = post_reload(Client(), user, source, reload_request_id=request_id)

    assert response.status_code == 200, response.content
    assert TripIngestion.objects.filter(
        user=user,
        client_session_id=reload_client_session_id(user, source, request_id),
    ).count() == 1
    assert Trip.objects.filter(user=user, reloaded_from_trip=source).count() == 1


@pytest.mark.django_db
def test_direct_reload_rejected_while_user_has_active_trip(
    user, source_owner, object_storage
):
    source_start = datetime(2026, 6, 12, 10, tzinfo=dt_timezone.utc)
    source = make_reloadable_trip(source_owner, source_start=source_start)
    add_raw_sensor_part(source, object_storage, source_start=source_start)
    TripIngestion.objects.create(
        user=user,
        client_session_id="active-recording",
        device_id="device-a",
        recording_started_at=timezone.now(),
    )

    response = post_reload(Client(), user, source, reload_request_id="while-active")

    assert response.status_code == 409
    assert not Trip.objects.filter(user=user, reloaded_from_trip=source).exists()


@pytest.mark.django_db
def test_direct_reload_same_request_survives_source_unpublishing(
    user, source_owner, monkeypatch, object_storage, har_delays
):
    source_start = datetime(2026, 6, 12, 10, tzinfo=dt_timezone.utc)
    source = make_reloadable_trip(source_owner, source_start=source_start)
    add_raw_sensor_part(source, object_storage, source_start=source_start)
    monkeypatch.setattr(
        "mobility.api.timezone.now",
        lambda: datetime(2026, 6, 30, 15, tzinfo=dt_timezone.utc),
    )

    first = post_reload(Client(), user, source, reload_request_id="same-before-unpublish")
    source.is_reloadable = False
    source.save(update_fields=["is_reloadable", "updated_at"])
    retry = post_reload(Client(), user, source, reload_request_id="same-before-unpublish")
    new_request = post_reload(Client(), user, source, reload_request_id="after-unpublish")

    assert first.status_code == 200, first.content
    assert retry.status_code == 200, retry.content
    assert retry.json()["trip_id"] == first.json()["trip_id"]
    assert new_request.status_code == 409
    assert Trip.objects.filter(user=user, reloaded_from_trip=source).count() == 1


@pytest.mark.django_db
def test_direct_reload_regenerates_shifted_raw_sensor_object(
    user, source_owner, monkeypatch, object_storage, har_delays
):
    source_start = datetime(2026, 6, 12, 10, tzinfo=dt_timezone.utc)
    reload_now = datetime(2026, 6, 30, 15, tzinfo=dt_timezone.utc)
    source = make_reloadable_trip(source_owner, source_start=source_start)
    source_key, source_body = add_raw_sensor_part(
        source,
        object_storage,
        source_start=source_start,
    )
    monkeypatch.setattr("mobility.api.timezone.now", lambda: reload_now)

    response = post_reload(Client(), user, source, reload_request_id="with-raw")

    assert response.status_code == 200, response.content
    ingestion = TripIngestion.objects.get(id=response.json()["ingestion_id"])
    part = ingestion.parts.get(kind=PartKind.SENSOR_WINDOWS)
    assert part.object_key == f"ingestions/{ingestion.id}/sensor_windows_0001.json.gz"
    assert part.received_at == reload_now
    assert part.size_bytes == len(object_storage[part.object_key])
    assert part.sha256 == hashlib.sha256(object_storage[part.object_key]).hexdigest()
    assert json.loads(gzip.decompress(object_storage[source_key])) == source_body

    regenerated = json.loads(
        gzip.decompress(object_storage[part.object_key]).decode("utf-8")
    )
    window = regenerated["windows"][0]
    assert window["window_start"] == "2026-06-30T14:41:00Z"
    assert window["window_end"] == "2026-06-30T14:41:05Z"
    assert window["samples"] == source_body["windows"][0]["samples"]


@pytest.mark.django_db
def test_direct_reload_rejects_source_without_raw_sensor_evidence(
    user, source_owner, monkeypatch, object_storage, har_delays
):
    source = make_reloadable_trip(
        source_owner,
        source_start=datetime(2026, 6, 12, 10, tzinfo=dt_timezone.utc),
    )
    monkeypatch.setattr(
        "mobility.api.timezone.now",
        lambda: datetime(2026, 6, 30, 15, tzinfo=dt_timezone.utc),
    )

    response = post_reload(Client(), user, source, reload_request_id="missing-raw")

    assert response.status_code == 409
    assert Trip.objects.filter(user=user, reloaded_from_trip=source).count() == 0
    assert TripIngestion.objects.filter(
        user=user,
        client_session_id__startswith="reload-",
    ).count() == 0


@pytest.mark.django_db
def test_direct_reload_rejects_other_users_source(
    user, other_source_owner, monkeypatch, object_storage, har_delays
):
    source_start = datetime(2026, 6, 12, 10, tzinfo=dt_timezone.utc)
    source = make_reloadable_trip(other_source_owner, source_start=source_start)
    add_raw_sensor_part(source, object_storage, source_start=source_start)
    monkeypatch.setattr(
        "mobility.api.timezone.now",
        lambda: datetime(2026, 6, 30, 15, tzinfo=dt_timezone.utc),
    )

    response = post_reload(Client(), user, source, reload_request_id="other-source")

    assert response.status_code == 404
    assert Trip.objects.filter(user=user, reloaded_from_trip=source).count() == 0


@pytest.mark.django_db
def test_direct_reload_storage_failure_leaves_no_visible_partial_trip(
    user, source_owner, monkeypatch, object_storage, har_delays
):
    source_start = datetime(2026, 6, 12, 10, tzinfo=dt_timezone.utc)
    source = make_reloadable_trip(source_owner, source_start=source_start)
    source_key, _ = add_raw_sensor_part(
        source,
        object_storage,
        source_start=source_start,
    )
    second_source_key, _ = add_raw_sensor_part(
        source,
        object_storage,
        source_start=source_start,
        sequence=2,
        minute=2,
    )
    source_part_keys_before = set(
        TripIngestionPart.objects.filter(
            ingestion__trip=source,
            kind=PartKind.SENSOR_WINDOWS,
        ).values_list("object_key", flat=True)
    )
    source_objects_before = {
        source_key: object_storage[source_key],
        second_source_key: object_storage[second_source_key],
    }
    monkeypatch.setattr(
        "mobility.api.timezone.now",
        lambda: datetime(2026, 6, 30, 15, tzinfo=dt_timezone.utc),
    )
    written_reload_keys: list[str] = []

    def fail_second_reload_write(object_key, body, **_kwargs):
        if object_key.startswith("ingestions/") and not written_reload_keys:
            object_storage[object_key] = body
            written_reload_keys.append(object_key)
            return
        raise OSError("bucket down")

    monkeypatch.setattr(
        "mobility.replay_raw.storage.write_object", fail_second_reload_write
    )

    response = post_reload(Client(), user, source, reload_request_id="storage-fails")

    assert response.status_code == 503
    assert written_reload_keys
    assert written_reload_keys[0] not in object_storage
    assert Trip.objects.filter(user=user, reloaded_from_trip=source).count() == 0
    assert TripIngestion.objects.filter(
        user=user,
        client_session_id__startswith="reload-",
    ).count() == 0
    assert HarJob.objects.filter(trip__reloaded_from_trip=source).count() == 0
    assert set(
        TripIngestionPart.objects.filter(
            ingestion__trip=source,
            kind=PartKind.SENSOR_WINDOWS,
        ).values_list("object_key", flat=True)
    ) == source_part_keys_before
    assert object_storage[source_key] == source_objects_before[source_key]
    assert object_storage[second_source_key] == source_objects_before[second_source_key]


@pytest.mark.django_db
def test_direct_reload_queues_har_and_keeps_track_visible(
    user,
    source_owner,
    monkeypatch,
    object_storage,
    har_delays,
    django_capture_on_commit_callbacks,
):
    source_start = datetime(2026, 6, 12, 10, tzinfo=dt_timezone.utc)
    source = make_reloadable_trip(source_owner, source_start=source_start)
    add_raw_sensor_part(source, object_storage, source_start=source_start)
    monkeypatch.setattr(
        "mobility.api.timezone.now",
        lambda: datetime(2026, 6, 30, 15, tzinfo=dt_timezone.utc),
    )

    with django_capture_on_commit_callbacks(execute=True) as callbacks:
        response = post_reload(Client(), user, source, reload_request_id="queue-har")

    assert response.status_code == 200, response.content
    data = response.json()
    assert data["raw_status"] == TripIngestion.PhaseStatus.QUEUED

    ingestion = TripIngestion.objects.get(id=data["ingestion_id"])
    job = HarJob.objects.get(trip_id=data["trip_id"], kind=HarJob.Kind.FINAL_TRIP)
    assert ingestion.raw_status == TripIngestion.PhaseStatus.QUEUED
    assert ingestion.queued_at == datetime(2026, 6, 30, 15, tzinfo=dt_timezone.utc)
    assert len(callbacks) == 1
    assert har_delays == [(job.id, ingestion.id)]

    track = Client().get(
        f"/api/mobility/trips/{data['trip_id']}/track",
        **auth_headers(user),
    )
    assert track.status_code == 200
    assert track.json()["point_count"] == 2
    assert track.json()["geojson"] is not None


def post_start(user, body):
    return Client().post(
        "/api/ingestion/trips/start",
        data=json.dumps(body),
        content_type="application/json",
        **auth_headers(user),
    )


@pytest.mark.django_db
def test_start_with_source_trip_marks_replay_ingestion(user, source_owner):
    source = make_reloadable_trip(
        source_owner, source_start=datetime(2026, 6, 12, 10, tzinfo=dt_timezone.utc)
    )

    response = post_start(
        user,
        {"client_session_id": "replay-1", "source_trip_id": source.id},
    )

    assert response.status_code == 200, response.content
    ingestion = TripIngestion.objects.get(id=response.json()["ingestion_id"])
    assert ingestion.source_trip_id == source.id
    assert ingestion.recording_started_at is not None


@pytest.mark.django_db
def test_start_with_non_reloadable_source_is_rejected(user, source_owner):
    source = make_reloadable_trip(
        source_owner, source_start=datetime(2026, 6, 12, 10, tzinfo=dt_timezone.utc)
    )
    source.is_reloadable = False
    source.save(update_fields=["is_reloadable", "updated_at"])

    response = post_start(
        user,
        {"client_session_id": "replay-2", "source_trip_id": source.id},
    )

    assert response.status_code == 409
    assert not TripIngestion.objects.filter(client_session_id="replay-2").exists()


@pytest.mark.django_db
def test_start_with_other_users_source_is_rejected(user, other_source_owner):
    source = make_reloadable_trip(
        other_source_owner,
        source_start=datetime(2026, 6, 12, 10, tzinfo=dt_timezone.utc),
    )

    response = post_start(
        user,
        {"client_session_id": "replay-other", "source_trip_id": source.id},
    )

    assert response.status_code == 409
    assert not TripIngestion.objects.filter(client_session_id="replay-other").exists()


@pytest.mark.django_db
def test_replay_data_returns_owner_source_track(user, source_owner):
    source_start = datetime(2026, 6, 12, 10, tzinfo=dt_timezone.utc)
    source = make_reloadable_trip(source_owner, source_start=source_start)

    response = Client().get(
        f"/api/mobility/trips/reloadable/{source.id}/replay-data",
        **auth_headers(user),
    )

    assert response.status_code == 200, response.content
    data = response.json()
    assert data["source_trip_id"] == source.id
    assert len(data["gps_points"]) == 2
    timestamps = [point["timestamp"] for point in data["gps_points"]]
    assert timestamps == sorted(timestamps)
    assert len(data["state_transitions"]) == 1


@pytest.mark.django_db
def test_replay_data_rejects_other_users_source(user, other_source_owner):
    source_start = datetime(2026, 6, 12, 10, tzinfo=dt_timezone.utc)
    source = make_reloadable_trip(other_source_owner, source_start=source_start)

    response = Client().get(
        f"/api/mobility/trips/reloadable/{source.id}/replay-data",
        **auth_headers(user),
    )

    assert response.status_code == 404


@pytest.mark.django_db
def test_replay_data_rejects_non_reloadable_trip(user, source_owner):
    source_start = datetime(2026, 6, 12, 10, tzinfo=dt_timezone.utc)
    source = make_reloadable_trip(source_owner, source_start=source_start)
    source.is_reloadable = False
    source.save(update_fields=["is_reloadable", "updated_at"])

    response = Client().get(
        f"/api/mobility/trips/reloadable/{source.id}/replay-data",
        **auth_headers(user),
    )

    assert response.status_code == 404


def _stable_json(data: dict) -> bytes:
    return json.dumps(
        data, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    ).encode("utf-8")


def signed_core(body: dict) -> dict:
    source = {k: v for k, v in body.items() if k != "core_payload_sha256"}
    return {**body, "core_payload_sha256": hashlib.sha256(_stable_json(source)).hexdigest()}


def post_core(user, body: dict):
    return Client().post(
        "/api/ingestion/trips/core",
        data=_stable_json(body).decode("utf-8"),
        content_type="application/json",
        **auth_headers(user),
    )


@pytest.mark.django_db
def test_replay_stop_rejects_selected_start_that_overlaps_user_trip(
    user, source_owner, monkeypatch
):
    source_start = datetime(2026, 6, 12, 10, tzinfo=dt_timezone.utc)
    source = make_reloadable_trip(source_owner, source_start=source_start)
    Trip.objects.create(
        user=user,
        device_id="existing",
        status=Trip.Status.CLOSED,
        started_at=datetime(2026, 6, 29, 12, 20, tzinfo=dt_timezone.utc),
        ended_at=datetime(2026, 6, 29, 12, 40, tzinfo=dt_timezone.utc),
    )
    start = post_start(
        user,
        {
            "client_session_id": "replay-overlap",
            "device_id": "replay-device",
            "source_trip_id": source.id,
        },
    )
    monkeypatch.setattr(
        "mobility.ingestion.api.timezone.now",
        lambda: datetime(2026, 6, 30, 15, tzinfo=dt_timezone.utc),
    )

    response = post_core(
        user,
        signed_core(
            {
                "ingestion_id": start.json()["ingestion_id"],
                "cutoff_source_timestamp": "2026-06-12T10:20:00Z",
                "client_session_id": "replay-overlap",
                "schema_version": 1,
                "started_at": "2026-06-29T12:15:00Z",
                "ended_at": "2026-06-29T12:35:00Z",
                "timezone": "Europe/Rome",
                "device_id": "replay-device",
                "app_version": "",
                "device_platform": "",
                "gps_points": [
                        {
                            "timestamp": "2026-06-29T12:15:00Z",
                            "latitude": 45.40,
                            "longitude": 9.10,
                            "speed_mps": 1.0,
                            "accuracy_meters": 7.0,
                        },
                        {
                            "timestamp": "2026-06-29T12:35:00Z",
                            "latitude": 45.50,
                            "longitude": 9.20,
                            "speed_mps": 2.0,
                            "accuracy_meters": 8.0,
                        },
                ],
                "state_transitions": [],
                "expected_raw_parts": {},
            }
        ),
    )

    assert response.status_code == 409
    assert not Trip.objects.filter(client_session_id="replay-overlap").exists()


@pytest.mark.django_db
def test_replay_stop_materializes_trip_and_regenerates_raw_up_to_cutoff(
    user, source_owner, object_storage, har_delays, django_capture_on_commit_callbacks
):
    source_start = datetime(2026, 6, 12, 10, tzinfo=dt_timezone.utc)
    source = make_reloadable_trip(source_owner, source_start=source_start)
    add_raw_sensor_part(source, object_storage, source_start=source_start, minute=1)
    add_raw_sensor_part(
        source, object_storage, source_start=source_start, sequence=2, minute=15
    )
    cutoff = source_start + timedelta(minutes=10)  # esclude la window al minuto 15

    start = post_start(
        user,
        {
            "client_session_id": "replay-stop",
            "device_id": "replay-device",
            "source_trip_id": source.id,
        },
    )
    ingestion_id = start.json()["ingestion_id"]

    reload_end = datetime(2026, 6, 30, 15, tzinfo=dt_timezone.utc)
    body = signed_core(
        {
            "ingestion_id": ingestion_id,
            "cutoff_source_timestamp": "2026-06-12T10:10:00Z",
            "client_session_id": "replay-stop",
            "schema_version": 1,
            "started_at": "2026-06-30T14:45:00Z",
            "ended_at": "2026-06-30T15:00:00Z",
            "timezone": "Europe/Rome",
            "device_id": "replay-device",
            "app_version": "",
            "device_platform": "",
            "gps_points": [
                {
                    "timestamp": "2026-06-30T14:45:00Z",
                    "latitude": 45.40,
                    "longitude": 9.10,
                    "speed_mps": 1.0,
                    "accuracy_meters": 7.0,
                },
                {
                    "timestamp": "2026-06-30T15:00:00Z",
                    "latitude": 45.50,
                    "longitude": 9.20,
                    "speed_mps": 2.0,
                    "accuracy_meters": 8.0,
                },
            ],
            "state_transitions": [],
            "expected_raw_parts": {},
        }
    )

    with django_capture_on_commit_callbacks(execute=True):
        response = post_core(user, body)

    assert response.status_code == 200, response.content
    data = response.json()
    trip = Trip.objects.get(id=data["trip_id"])
    assert trip.user_id == user.id
    assert trip.reloaded_from_trip_id == source.id
    # Una sola parte raw rigenerata: quella al minuto 1, non quella al minuto 15.
    parts = TripIngestionPart.objects.filter(ingestion_id=ingestion_id)
    assert parts.count() == 1
    regenerated = json.loads(gzip.decompress(object_storage[parts.first().object_key]))
    window_start = regenerated["windows"][0]["window_start"]
    # 10:01 sorgente + shift (15:00@06-30 - 10:10@06-12) = 14:51@06-30.
    assert window_start == "2026-06-30T14:51:00Z"
    assert har_delays  # HAR finale accodato
    ingestion = TripIngestion.objects.get(id=ingestion_id)
    assert ingestion.raw_status == TripIngestion.PhaseStatus.QUEUED
    assert ingestion.recording_closed_at is not None
