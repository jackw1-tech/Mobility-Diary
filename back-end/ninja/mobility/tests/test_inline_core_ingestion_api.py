import copy
import hashlib
import json

import pytest
from django.conf import settings
from django.contrib.auth import get_user_model
from django.test import Client

from accounts.models import AccessToken
from mobility.models import (
    GpsPoint,
    PartKind,
    StateTransition,
    Trip,
    TripIngestion,
    TripIngestionPart,
)


@pytest.fixture
def user(db):
    return get_user_model().objects.create_user(
        username="inline-owner@example.com",
        email="inline-owner@example.com",
        password="password",
    )


@pytest.fixture
def other_user(db):
    return get_user_model().objects.create_user(
        username="inline-other@example.com",
        email="inline-other@example.com",
        password="password",
    )


def auth_headers(user):
    raw_token, _ = AccessToken.issue_for_user(user)
    return {"HTTP_AUTHORIZATION": f"Bearer {raw_token}"}


def stable_json(data: dict) -> bytes:
    return json.dumps(
        data,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode("utf-8")


def add_hash(payload: dict) -> dict:
    data = copy.deepcopy(payload)
    hash_source = copy.deepcopy(data)
    hash_source.pop("core_payload_sha256", None)
    data["core_payload_sha256"] = hashlib.sha256(stable_json(hash_source)).hexdigest()
    return data


def base_payload(**overrides) -> dict:
    payload = {
        "client_session_id": "inline-session",
        "schema_version": 1,
        "started_at": "2026-06-12T10:00:00Z",
        "ended_at": "2026-06-12T10:30:00Z",
        "timezone": "Europe/Rome",
        "device_id": "test-device",
        "app_version": "1.0.0",
        "device_platform": "ios",
        "gps_points": [
            {
                "timestamp": "2026-06-12T10:02:00Z",
                "latitude": 45.47,
                "longitude": 9.20,
                "speed_mps": 2.0,
                "accuracy_meters": 8.0,
            },
            {
                "timestamp": "2026-06-12T10:01:00Z",
                "latitude": 45.46,
                "longitude": 9.10,
                "speed_mps": 1.0,
                "accuracy_meters": 7.0,
            },
        ],
        "state_transitions": [
            {
                "timestamp": "2026-06-12T10:03:00Z",
                "from_state": "STATIONARY",
                "to_state": "ACTIVE_TRACKING",
                "reason": "test",
                "sigma": 1.4,
                "speed_mps": 2.0,
            }
        ],
        "expected_raw_parts": {"sensor_windows": 2},
    }
    payload.update(overrides)
    return payload


def post_inline(client: Client, user, payload: dict):
    return client.post(
        "/api/ingestion/trips/core",
        data=stable_json(payload).decode("utf-8"),
        content_type="application/json",
        **auth_headers(user),
    )


@pytest.mark.django_db
def test_inline_core_happy_path_materializes_trip_and_path(user):
    payload = add_hash(base_payload())

    response = post_inline(Client(), user, payload)

    assert response.status_code == 200, response.content
    data = response.json()
    assert data["core_status"] == TripIngestion.PhaseStatus.COMPLETED
    assert data["raw_status"] == TripIngestion.PhaseStatus.PENDING
    assert data["gps_points"] == 2
    assert data["state_transitions"] == 1
    assert data["path_points"] == 2
    assert data["distance_meters"] > 0
    assert data["map_available"] is True

    ingestion = TripIngestion.objects.get(client_session_id="inline-session")
    assert ingestion.user_id == user.id
    assert ingestion.core_ingestion_mode == TripIngestion.CoreIngestionMode.INLINE
    assert ingestion.core_payload_sha256 == payload["core_payload_sha256"]
    assert ingestion.core_payload_size_bytes > 0
    assert ingestion.expected_core_parts == {}
    assert ingestion.expected_raw_parts == {"sensor_windows": 2}
    assert ingestion.trip_id == data["trip_id"]

    trip = ingestion.trip
    assert trip.user_id == user.id
    assert GpsPoint.objects.filter(trip=trip).count() == 2
    assert StateTransition.objects.filter(trip=trip).count() == 1
    assert list(trip.path.coords) == [(9.10, 45.46), (9.20, 45.47)]
    assert (
        TripIngestionPart.objects.filter(
            ingestion=ingestion,
            kind__in=[PartKind.GPS_POINTS, PartKind.STATE_TRANSITIONS],
        ).count()
        == 0
    )


@pytest.mark.django_db
def test_inline_core_same_hash_retry_is_idempotent(user):
    payload = add_hash(base_payload(client_session_id="inline-idempotent"))
    client = Client()

    first = post_inline(client, user, payload)
    second = post_inline(client, user, payload)

    assert first.status_code == 200
    assert second.status_code == 200
    assert second.json()["ingestion_id"] == first.json()["ingestion_id"]
    assert second.json()["trip_id"] == first.json()["trip_id"]
    trip_id = first.json()["trip_id"]
    assert (
        TripIngestion.objects.filter(client_session_id="inline-idempotent").count()
        == 1
    )
    assert Trip.objects.filter(client_session_id="inline-idempotent").count() == 1
    assert GpsPoint.objects.filter(trip_id=trip_id).count() == 2
    assert StateTransition.objects.filter(trip_id=trip_id).count() == 1


@pytest.mark.django_db
def test_inline_core_different_hash_for_same_session_conflicts(user):
    first_payload = add_hash(base_payload(client_session_id="inline-conflict"))
    second_source = base_payload(client_session_id="inline-conflict")
    second_source["gps_points"][0]["latitude"] = 46.0
    second_payload = add_hash(second_source)
    client = Client()

    first = post_inline(client, user, first_payload)
    second = post_inline(client, user, second_payload)

    assert first.status_code == 200
    assert second.status_code == 409
    assert (
        TripIngestion.objects.filter(client_session_id="inline-conflict").count() == 1
    )


@pytest.mark.django_db
def test_inline_core_hash_mismatch_returns_400(user):
    payload = add_hash(base_payload(client_session_id="inline-bad-hash"))
    payload["gps_points"][0]["latitude"] = 46.0

    response = post_inline(Client(), user, payload)

    assert response.status_code == 400


@pytest.mark.django_db
def test_inline_core_empty_payload_returns_400(user):
    payload = add_hash(
        base_payload(
            client_session_id="inline-empty",
            gps_points=[],
            state_transitions=[],
        )
    )

    response = post_inline(Client(), user, payload)

    assert response.status_code == 400
    assert not TripIngestion.objects.filter(client_session_id="inline-empty").exists()


@pytest.mark.django_db
def test_inline_core_payload_over_limit_returns_413(user):
    payload = add_hash(
        base_payload(
            client_session_id="inline-too-large",
            device_id="x" * settings.INGESTION_INLINE_CORE_MAX_BYTES,
        )
    )

    response = post_inline(Client(), user, payload)

    assert response.status_code == 413
    assert not TripIngestion.objects.filter(
        client_session_id="inline-too-large"
    ).exists()


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("gps_points", "state_transitions", "map_available", "raw_status"),
    [
        (base_payload()["gps_points"], [], True, TripIngestion.PhaseStatus.COMPLETED),
        (
            [],
            base_payload()["state_transitions"],
            False,
            TripIngestion.PhaseStatus.COMPLETED,
        ),
    ],
)
def test_inline_core_accepts_gps_only_or_transitions_only(
    user,
    gps_points,
    state_transitions,
    map_available,
    raw_status,
):
    payload = add_hash(
        base_payload(
            client_session_id=f"inline-partial-{map_available}",
            gps_points=gps_points,
            state_transitions=state_transitions,
            expected_raw_parts={},
        )
    )

    response = post_inline(Client(), user, payload)

    assert response.status_code == 200, response.content
    data = response.json()
    assert data["core_status"] == TripIngestion.PhaseStatus.COMPLETED
    assert data["raw_status"] == raw_status
    assert data["map_available"] is map_available


@pytest.mark.django_db
@pytest.mark.parametrize(
    "core_status",
    [TripIngestion.PhaseStatus.QUEUED, TripIngestion.PhaseStatus.PROCESSING],
)
def test_inline_core_returns_current_state_for_legacy_processing(user, core_status):
    ingestion = TripIngestion.objects.create(
        user=user,
        client_session_id=f"inline-legacy-{core_status}",
        core_status=core_status,
        raw_status=TripIngestion.PhaseStatus.PENDING,
    )
    payload = add_hash(base_payload(client_session_id=ingestion.client_session_id))

    response = post_inline(Client(), user, payload)

    assert response.status_code == 200
    data = response.json()
    assert data["ingestion_id"] == ingestion.id
    assert data["core_status"] == core_status
    ingestion.refresh_from_db()
    assert ingestion.core_ingestion_mode == TripIngestion.CoreIngestionMode.LEGACY_PARTS
    assert ingestion.trip_id is None


@pytest.mark.django_db
def test_inline_core_failed_final_conflicts(user):
    TripIngestion.objects.create(
        user=user,
        client_session_id="inline-failed-final",
        core_status=TripIngestion.PhaseStatus.FAILED_FINAL,
    )
    payload = add_hash(base_payload(client_session_id="inline-failed-final"))

    response = post_inline(Client(), user, payload)

    assert response.status_code == 409


@pytest.mark.django_db
def test_complete_raw_rejects_until_core_is_completed(user):
    ingestion = TripIngestion.objects.create(
        user=user,
        client_session_id="raw-before-core",
        core_status=TripIngestion.PhaseStatus.PENDING,
        raw_status=TripIngestion.PhaseStatus.PENDING,
        expected_raw_parts={"sensor_windows": 1},
    )

    response = Client().post(
        f"/api/ingestion/trips/{ingestion.id}/complete-raw",
        data=stable_json({"total_parts": 1}).decode("utf-8"),
        content_type="application/json",
        **auth_headers(user),
    )

    assert response.status_code == 409
    ingestion.refresh_from_db()
    assert ingestion.raw_status == TripIngestion.PhaseStatus.PENDING


@pytest.mark.django_db
def test_inline_core_does_not_reuse_trip_owned_by_another_user(user, other_user):
    Trip.objects.create(
        user=other_user,
        client_session_id="inline-cross-user",
        device_id="other-device",
        status=Trip.Status.CLOSED,
    )
    payload = add_hash(base_payload(client_session_id="inline-cross-user"))

    response = post_inline(Client(), user, payload)

    assert response.status_code == 409
    assert not TripIngestion.objects.filter(
        user=user,
        client_session_id="inline-cross-user",
    ).exists()
