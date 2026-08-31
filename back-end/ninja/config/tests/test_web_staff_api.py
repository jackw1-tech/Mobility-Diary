import json

import pytest
from django.contrib.auth import get_user_model

from .conftest import TEST_PASSWORD
from .test_ingestion_and_trips_api import complete_core, start_recording


pytestmark = pytest.mark.django_db


@pytest.fixture
def staff_user():
    return get_user_model().objects.create_user(
        username="staff@example.com",
        email="staff@example.com",
        password=TEST_PASSWORD,
        first_name="Staff",
        last_name="Mobility",
        is_staff=True,
    )


def web_login(api_client, email="staff@example.com", password=TEST_PASSWORD):
    return api_client.post(
        "/api/web/auth/login",
        data=json.dumps({"email": email, "password": password}),
        content_type="application/json",
    )


def web_headers(auth_payload):
    return {"HTTP_AUTHORIZATION": f"Bearer {auth_payload['access_token']}"}


def test_only_staff_can_log_into_the_web_dashboard(
    api_client, staff_user, register_mobile_user
):
    mobile = register_mobile_user("participant@example.com")

    staff_login = web_login(api_client)
    participant_login = web_login(api_client, email="participant@example.com")

    assert mobile.status_code == 201
    assert staff_login.status_code == 200
    assert staff_login.json()["user"]["is_staff"] is True
    assert participant_login.status_code == 403
    assert participant_login.json() == {"detail": "Accesso staff richiesto"}


def test_web_refresh_rotation_and_logout_invalidate_old_tokens(
    api_client, staff_user
):
    first = web_login(api_client).json()
    rotated = api_client.post(
        "/api/web/auth/refresh",
        data=json.dumps({"refresh_token": first["refresh_token"]}),
        content_type="application/json",
    )
    old_retry = api_client.post(
        "/api/web/auth/refresh",
        data=json.dumps({"refresh_token": first["refresh_token"]}),
        content_type="application/json",
    )
    logout = api_client.post(
        "/api/web/auth/logout",
        data=json.dumps({"refresh_token": rotated.json()["refresh_token"]}),
        content_type="application/json",
    )
    after_logout = api_client.post(
        "/api/web/auth/refresh",
        data=json.dumps({"refresh_token": rotated.json()["refresh_token"]}),
        content_type="application/json",
    )

    assert rotated.status_code == 200
    assert rotated.json()["refresh_token"] != first["refresh_token"]
    assert old_retry.status_code == 401
    assert logout.status_code == 200
    assert after_logout.status_code == 401


def test_staff_can_browse_owners_trips_and_privacy_dashboard(
    api_client, staff_user, mobile_session
):
    mobile_headers = mobile_session["headers"]
    ingestion_id = start_recording(api_client, mobile_headers).json()["ingestion_id"]
    trip_id = complete_core(api_client, mobile_headers, ingestion_id).json()["trip_id"]
    owner_id = mobile_session["user"]["id"]
    auth = web_login(api_client).json()
    headers = web_headers(auth)

    users = api_client.get("/api/web/users", **headers)
    trips = api_client.get(f"/api/web/users/{owner_id}/trips", **headers)
    dashboard = api_client.get(
        f"/api/web/users/{owner_id}/trips/{trip_id}?level=aggregated",
        **headers,
    )

    assert users.status_code == 200
    owner = next(user for user in users.json() if user["id"] == owner_id)
    assert owner["trip_count"] == 1
    assert trips.status_code == 200
    assert trips.json()["trips"][0]["id"] == trip_id
    assert dashboard.status_code == 200
    assert dashboard.json()["owner"]["id"] == owner_id
    assert dashboard.json()["track"]["point_count"] == 2
    assert dashboard.json()["privacy_aware"]["level"] == "aggregated"
    assert dashboard.json()["privacy_aware"]["track"]["geojson"] != dashboard.json()["track"]["geojson"]


def test_web_trip_filters_are_validated(api_client, staff_user, mobile_session):
    owner_id = mobile_session["user"]["id"]
    headers = web_headers(web_login(api_client).json())

    response = api_client.get(
        f"/api/web/users/{owner_id}/trips?processed=maybe",
        **headers,
    )

    assert response.status_code == 422
    assert response.json() == {"detail": "Filtro processed non valido"}


def test_web_endpoints_reject_mobile_and_invalid_tokens(
    api_client, mobile_session, staff_user
):
    assert api_client.get("/api/web/users").status_code == 401
    assert (
        api_client.get(
            "/api/web/users",
            HTTP_AUTHORIZATION=f"Bearer {mobile_session['token']}",
        ).status_code
        == 401
    )
