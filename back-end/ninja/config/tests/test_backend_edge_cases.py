import json

import pytest
from django.contrib.auth import get_user_model
from django.utils import timezone

from mobility.models import TripIngestion

from .conftest import TEST_PASSWORD
from .test_ingestion_and_trips_api import (
    STARTED_AT,
    complete_core,
    start_recording,
)


pytestmark = pytest.mark.django_db


def post_json(client, path, payload, headers=None):
    return client.post(
        path,
        data=json.dumps(payload),
        content_type="application/json",
        **(headers or {}),
    )


def test_registration_rejects_invalid_email(register_mobile_user):
    response = register_mobile_user("not-an-email")

    assert response.status_code == 400
    assert response.json() == {"detail": "Email non valida"}


def test_registration_rejects_weak_password(register_mobile_user):
    response = register_mobile_user("weak@example.com", password="password")

    assert response.status_code == 400
    assert "password" in response.json()["detail"].lower()


def test_invalid_privacy_level_does_not_change_the_saved_preference(
    api_client, mobile_session
):
    headers = mobile_session["headers"]

    rejected = api_client.put(
        "/api/privacy/settings",
        data=json.dumps({"privacy_level": "secret-future-level"}),
        content_type="application/json",
        **headers,
    )
    current = api_client.get("/api/privacy/settings", **headers)

    assert rejected.status_code == 400
    assert rejected.json() == {"detail": "Livello privacy non valido"}
    assert current.json() == {
        "privacy_level": "precise",
        "is_first_login": True,
    }


@pytest.mark.xfail(
    strict=True,
    reason="known bug: mobile login does not normalize email like registration",
)
def test_mobile_login_treats_email_as_case_insensitive(
    api_client, register_mobile_user
):
    assert register_mobile_user("mixed.case@example.com").status_code == 201

    response = post_json(
        api_client,
        "/api/auth/login",
        {"email": "  MIXED.CASE@EXAMPLE.COM  ", "password": TEST_PASSWORD},
    )

    assert response.status_code == 200
    assert response.json()["user"]["email"] == "mixed.case@example.com"


@pytest.mark.xfail(
    strict=True,
    reason="known bug: Django authenticate hides inactive users before 403 handling",
)
def test_disabled_mobile_user_receives_the_documented_forbidden_response(
    api_client, register_mobile_user
):
    assert register_mobile_user("disabled@example.com").status_code == 201
    get_user_model().objects.filter(email="disabled@example.com").update(
        is_active=False
    )

    response = post_json(
        api_client,
        "/api/auth/login",
        {"email": "disabled@example.com", "password": TEST_PASSWORD},
    )

    assert response.status_code == 403
    assert response.json() == {"detail": "Utente disabilitato"}


@pytest.mark.xfail(
    strict=True,
    reason="known bug: heartbeat accepts an abandoned ingestion",
)
def test_abandoned_recording_rejects_heartbeat(api_client, mobile_session):
    headers = mobile_session["headers"]
    ingestion_id = start_recording(api_client, headers).json()["ingestion_id"]
    post_json(
        api_client,
        f"/api/ingestion/trips/{ingestion_id}/abandon",
        {"device_id": "iphone-mario"},
        headers,
    )

    response = post_json(
        api_client,
        f"/api/ingestion/trips/{ingestion_id}/heartbeat",
        {"client_session_id": "session-001", "device_id": "iphone-mario"},
        headers,
    )

    assert response.status_code == 410


@pytest.mark.xfail(
    strict=True,
    reason="known bug: core completion resurrects an abandoned ingestion",
)
def test_abandoned_recording_cannot_materialize_a_trip(
    api_client, mobile_session
):
    headers = mobile_session["headers"]
    ingestion_id = start_recording(api_client, headers).json()["ingestion_id"]
    post_json(
        api_client,
        f"/api/ingestion/trips/{ingestion_id}/abandon",
        {"device_id": "iphone-mario"},
        headers,
    )

    response = complete_core(api_client, headers, ingestion_id)

    assert response.status_code == 410
    assert api_client.get("/api/mobility/trips", **headers).json() == []


@pytest.mark.xfail(
    strict=True,
    reason="known bug: active lookup does not expire stale recordings",
)
def test_stale_recording_is_not_reported_as_resumable(
    api_client, mobile_session
):
    headers = mobile_session["headers"]
    ingestion_id = start_recording(api_client, headers).json()["ingestion_id"]
    TripIngestion.objects.filter(id=ingestion_id).update(
        last_seen_at=timezone.now() - timezone.timedelta(hours=25)
    )

    response = api_client.get("/api/ingestion/trips/active", **headers)

    assert response.status_code == 404
    assert response.json() == {"detail": "nessun viaggio in corso"}


@pytest.mark.xfail(
    strict=True,
    reason="known bug: heartbeat accepts an already closed ingestion",
)
def test_closed_recording_rejects_further_heartbeat(api_client, mobile_session):
    headers = mobile_session["headers"]
    ingestion_id = start_recording(api_client, headers).json()["ingestion_id"]
    assert complete_core(api_client, headers, ingestion_id).status_code == 200

    response = post_json(
        api_client,
        f"/api/ingestion/trips/{ingestion_id}/heartbeat",
        {"client_session_id": "session-001", "device_id": "iphone-mario"},
        headers,
    )

    assert response.status_code == 410


@pytest.mark.xfail(
    strict=True,
    reason="known bug: core ingestion accepts ended_at before started_at",
)
def test_core_rejects_an_end_before_the_recording_start(
    api_client, mobile_session
):
    headers = mobile_session["headers"]
    ingestion_id = start_recording(api_client, headers).json()["ingestion_id"]

    response = post_json(
        api_client,
        "/api/ingestion/trips/core",
        {
            "ingestion_id": ingestion_id,
            "client_session_id": "session-001",
            "device_id": "iphone-mario",
            "started_at": STARTED_AT,
            "ended_at": "2026-08-30T09:59:00Z",
            "state_transitions": [
                {
                    "timestamp": STARTED_AT,
                    "from_state": "STATIONARY",
                    "to_state": "MOVEMENT",
                }
            ],
        },
        headers,
    )

    assert response.status_code == 422


@pytest.mark.xfail(
    strict=True,
    reason="known bug: GPS coordinates are not validated against WGS84 bounds",
)
def test_core_rejects_coordinates_outside_wgs84_bounds(
    api_client, mobile_session
):
    headers = mobile_session["headers"]
    ingestion_id = start_recording(api_client, headers).json()["ingestion_id"]

    response = post_json(
        api_client,
        "/api/ingestion/trips/core",
        {
            "ingestion_id": ingestion_id,
            "client_session_id": "session-001",
            "device_id": "iphone-mario",
            "started_at": STARTED_AT,
            "ended_at": "2026-08-30T10:01:00Z",
            "gps_points": [
                {
                    "timestamp": STARTED_AT,
                    "latitude": 95,
                    "longitude": 9.19,
                }
            ],
        },
        headers,
    )

    assert response.status_code == 422


@pytest.mark.xfail(
    strict=True,
    reason="known bug: raw completion does not verify uploaded part coverage",
)
def test_raw_completion_rejects_missing_declared_parts(
    api_client, mobile_session
):
    headers = mobile_session["headers"]
    ingestion_id = start_recording(api_client, headers).json()["ingestion_id"]
    assert (
        complete_core(
            api_client,
            headers,
            ingestion_id,
            expected_raw_parts=1,
        ).status_code
        == 200
    )

    response = post_json(
        api_client,
        f"/api/ingestion/trips/{ingestion_id}/complete-raw",
        {"total_parts": 1},
        headers,
    )

    assert response.status_code == 409
    assert "mancanti" in response.json()["detail"]


@pytest.mark.xfail(
    strict=True,
    reason="known bug: raw completion without core raises database IntegrityError",
)
def test_raw_completion_requires_a_materialized_core_trip(
    api_client, mobile_session
):
    headers = mobile_session["headers"]
    ingestion_id = start_recording(api_client, headers).json()["ingestion_id"]

    response = post_json(
        api_client,
        f"/api/ingestion/trips/{ingestion_id}/complete-raw",
        {"total_parts": 0},
        headers,
    )

    assert response.status_code == 409
    assert response.json() == {"detail": "core ingestion non completata"}
