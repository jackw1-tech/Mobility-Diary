import json

import pytest
from django.contrib.auth import get_user_model
from django.contrib.gis.geos import Point
from django.utils import timezone

from accounts.models import AccessToken
from mobility.models import HabitualPlace, PlaceMiningStatus, TripIngestion

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


def test_note_rejects_more_than_five_hundred_characters(
    api_client, mobile_session
):
    headers = mobile_session["headers"]
    ingestion_id = start_recording(api_client, headers).json()["ingestion_id"]
    trip_id = complete_core(api_client, headers, ingestion_id).json()["trip_id"]

    response = api_client.patch(
        f"/api/mobility/trips/{trip_id}/note",
        data=json.dumps({"note": "x" * 501}),
        content_type="application/json",
        **headers,
    )

    assert response.status_code == 422
    assert response.json() == {"detail": "nota troppo lunga"}


def test_note_is_blocked_until_raw_ingestion_is_complete(
    api_client, mobile_session
):
    headers = mobile_session["headers"]
    ingestion_id = start_recording(api_client, headers).json()["ingestion_id"]
    trip_id = complete_core(
        api_client,
        headers,
        ingestion_id,
        expected_raw_parts=1,
    ).json()["trip_id"]

    response = api_client.patch(
        f"/api/mobility/trips/{trip_id}/note",
        data=json.dumps({"note": "non ancora"}),
        content_type="application/json",
        **headers,
    )

    assert response.status_code == 409
    assert response.json() == {
        "detail": "nota disponibile solo a viaggio completato"
    }


def test_other_user_cannot_edit_or_delete_a_trip(
    api_client, mobile_session, register_mobile_user
):
    owner_headers = mobile_session["headers"]
    ingestion_id = start_recording(api_client, owner_headers).json()["ingestion_id"]
    trip_id = complete_core(api_client, owner_headers, ingestion_id).json()["trip_id"]
    other = register_mobile_user("trip-attacker@example.com").json()
    other_headers = {
        "HTTP_AUTHORIZATION": f"Bearer {other['access_token']}"
    }

    note = api_client.patch(
        f"/api/mobility/trips/{trip_id}/note",
        data=json.dumps({"note": "changed by another user"}),
        content_type="application/json",
        **other_headers,
    )
    deletion = api_client.delete(
        f"/api/mobility/trips/{trip_id}", **other_headers
    )

    assert note.status_code == 404
    assert deletion.status_code == 404
    assert api_client.get(
        f"/api/mobility/trips/{trip_id}/track", **owner_headers
    ).status_code == 200


def test_route_assistant_rejects_a_malformed_sensor_window(
    api_client, mobile_session
):
    response = post_json(
        api_client,
        "/api/mobility/route-assistant/classify",
        {"samples": [[0.0] * 6]},
        mobile_session["headers"],
    )

    assert response.status_code == 422
    assert response.json() == {"detail": "finestra sensori non valida"}


def test_completed_trip_without_raw_telemetry_cannot_be_reloadable(
    api_client, mobile_session
):
    headers = mobile_session["headers"]
    ingestion_id = start_recording(api_client, headers).json()["ingestion_id"]
    trip_id = complete_core(api_client, headers, ingestion_id).json()["trip_id"]

    response = api_client.patch(
        f"/api/mobility/trips/{trip_id}/reloadable",
        data=json.dumps({"is_reloadable": True}),
        content_type="application/json",
        **headers,
    )

    assert response.status_code == 409
    assert response.json() == {"detail": "telemetrie sorgente non disponibili"}


def test_place_label_rejects_an_unknown_category(api_client, mobile_session):
    user_id = mobile_session["user"]["id"]
    place = HabitualPlace.objects.create(
        user_id=user_id,
        center=Point(9.19, 45.4642, srid=4326),
    )
    PlaceMiningStatus.objects.create(
        user_id=user_id,
        status=PlaceMiningStatus.Status.SUCCEEDED,
    )

    response = post_json(
        api_client,
        f"/api/mobility/places/{place.id}/label",
        {"category": "airport", "custom_name": "Malpensa"},
        mobile_session["headers"],
    )

    assert response.status_code == 422
    assert response.json() == {"detail": "categoria non valida"}


def test_negative_expected_raw_part_count_is_rejected(
    api_client, mobile_session
):
    headers = mobile_session["headers"]
    ingestion_id = start_recording(api_client, headers).json()["ingestion_id"]

    response = complete_core(
        api_client,
        headers,
        ingestion_id,
        expected_raw_parts=-1,
    )

    assert response.status_code == 422
    assert response.json() == {
        "detail": "expected_raw_parts contiene count non valido"
    }


def test_invalid_analytics_options_have_stable_safe_fallbacks(
    api_client, mobile_session
):
    response = api_client.get(
        "/api/mobility/analytics?granularity=quarter&tz=Not/AZone",
        **mobile_session["headers"],
    )

    assert response.status_code == 200
    assert response.json()["granularity"] == "day"
    assert response.json()["has_data"] is False


@pytest.mark.xfail(
    strict=True,
    reason="known bug: ingestion start accepts an empty client_session_id",
)
def test_start_rejects_an_empty_client_session_id(api_client, mobile_session):
    response = post_json(
        api_client,
        "/api/ingestion/trips/start",
        {
            "client_session_id": "",
            "device_id": "iphone-mario",
            "started_at": STARTED_AT,
        },
        mobile_session["headers"],
    )

    assert response.status_code == 422


@pytest.mark.xfail(
    strict=True,
    reason="known bug: GPS timestamps are not bounded by the trip interval",
)
def test_core_rejects_gps_points_outside_the_trip_interval(
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
                    "timestamp": "2026-08-30T12:00:00Z",
                    "latitude": 45.4642,
                    "longitude": 9.19,
                }
            ],
        },
        headers,
    )

    assert response.status_code == 422


@pytest.mark.xfail(
    strict=True,
    reason="known bug: cached mobile sessions bypass later user deactivation",
)
def test_mobile_token_stops_working_immediately_when_user_is_disabled(
    api_client, mobile_session
):
    get_user_model().objects.filter(id=mobile_session["user"]["id"]).update(
        is_active=False
    )

    response = api_client.get("/api/auth/me", **mobile_session["headers"])

    assert response.status_code == 401


@pytest.mark.xfail(
    strict=True,
    reason="known bug: cached mobile sessions ignore token expiry changed in DB",
)
def test_mobile_token_cache_observes_database_expiration(
    api_client, mobile_session
):
    AccessToken.objects.filter(
        token_hash=AccessToken.hash_raw_token(mobile_session["token"])
    ).update(expires_at=timezone.now() - timezone.timedelta(seconds=1))

    response = api_client.get("/api/auth/me", **mobile_session["headers"])

    assert response.status_code == 401


@pytest.mark.xfail(
    strict=True,
    reason="known bug: overlong place names reach PostgreSQL and raise DataError",
)
def test_place_label_rejects_names_longer_than_the_database_field(
    api_client, mobile_session
):
    user_id = mobile_session["user"]["id"]
    place = HabitualPlace.objects.create(
        user_id=user_id,
        center=Point(9.19, 45.4642, srid=4326),
    )
    PlaceMiningStatus.objects.create(
        user_id=user_id,
        status=PlaceMiningStatus.Status.SUCCEEDED,
    )

    response = post_json(
        api_client,
        f"/api/mobility/places/{place.id}/label",
        {"category": "altro", "custom_name": "x" * 129},
        mobile_session["headers"],
    )

    assert response.status_code == 422


@pytest.mark.xfail(
    strict=True,
    reason="known bug: web trip filters accept from later than to",
)
def test_web_trip_filters_reject_an_inverted_time_range(
    api_client, mobile_session
):
    from .test_web_staff_api import web_headers, web_login

    get_user_model().objects.create_user(
        username="staff@example.com",
        email="staff@example.com",
        password=TEST_PASSWORD,
        is_staff=True,
    )
    response = api_client.get(
        "/api/web/users/"
        f"{mobile_session['user']['id']}/trips"
        "?from=2026-08-31T12:00:00Z&to=2026-08-30T12:00:00Z",
        **web_headers(web_login(api_client).json()),
    )

    assert response.status_code == 422
