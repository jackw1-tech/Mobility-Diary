import json

import pytest

from .conftest import TEST_PASSWORD


pytestmark = pytest.mark.django_db


def test_registration_creates_an_authenticated_mobile_session(
    api_client, register_mobile_user
):
    response = register_mobile_user("  Mario.Rossi@Example.COM  ")

    assert response.status_code == 201
    payload = response.json()
    assert payload["token_type"] == "Bearer"
    assert payload["access_token"]
    assert payload["user"] == {
        "id": payload["user"]["id"],
        "email": "mario.rossi@example.com",
        "first_name": "Mario",
        "last_name": "Rossi",
        "is_staff": False,
        "is_superuser": False,
    }

    me = api_client.get(
        "/api/auth/me",
        HTTP_AUTHORIZATION=f"Bearer {payload['access_token']}",
    )
    assert me.status_code == 200
    assert me.json() == payload["user"]


def test_registration_rejects_a_duplicate_email(register_mobile_user):
    assert register_mobile_user("same@example.com").status_code == 201

    duplicate = register_mobile_user("SAME@example.com")

    assert duplicate.status_code == 409
    assert duplicate.json() == {"detail": "Email gia registrata"}


def test_login_rejects_invalid_credentials(api_client, register_mobile_user):
    assert register_mobile_user("login@example.com").status_code == 201

    response = api_client.post(
        "/api/auth/login",
        data=json.dumps(
            {"email": "login@example.com", "password": "wrong-password"}
        ),
        content_type="application/json",
    )

    assert response.status_code == 401
    assert response.json() == {"detail": "Credenziali non valide"}


def test_logout_invalidates_the_mobile_token(api_client, mobile_session):
    headers = mobile_session["headers"]

    logout = api_client.post("/api/auth/logout", HTTP_AUTHORIZATION=headers["HTTP_AUTHORIZATION"])
    after_logout = api_client.get("/api/auth/me", HTTP_AUTHORIZATION=headers["HTTP_AUTHORIZATION"])

    assert logout.status_code == 200
    assert logout.json() == {"detail": "Logout effettuato"}
    assert after_logout.status_code == 401


def test_privacy_preference_starts_precise_and_can_be_changed(
    api_client, mobile_session
):
    headers = mobile_session["headers"]

    initial = api_client.get("/api/privacy/settings", HTTP_AUTHORIZATION=headers["HTTP_AUTHORIZATION"])
    updated = api_client.put(
        "/api/privacy/settings",
        data=json.dumps({"privacy_level": "aggregated"}),
        content_type="application/json",
        HTTP_AUTHORIZATION=headers["HTTP_AUTHORIZATION"],
    )
    persisted = api_client.get("/api/privacy/settings", HTTP_AUTHORIZATION=headers["HTTP_AUTHORIZATION"])

    assert initial.status_code == 200
    assert initial.json() == {
        "privacy_level": "precise",
        "is_first_login": True,
    }
    assert updated.status_code == 200
    assert updated.json() == {
        "privacy_level": "aggregated",
        "is_first_login": False,
    }
    assert persisted.json() == updated.json()


def test_private_endpoints_require_a_valid_bearer_token(api_client):
    assert api_client.get("/api/auth/me").status_code == 401
    assert api_client.get("/api/privacy/settings").status_code == 401
    assert (
        api_client.get(
            "/api/mobility/trips",
            HTTP_AUTHORIZATION="Bearer not-a-real-token",
        ).status_code
        == 401
    )


def test_login_returns_a_new_working_token(api_client, register_mobile_user):
    assert register_mobile_user("returning@example.com").status_code == 201

    response = api_client.post(
        "/api/auth/login",
        data=json.dumps(
            {"email": "returning@example.com", "password": TEST_PASSWORD}
        ),
        content_type="application/json",
    )

    assert response.status_code == 200
    token = response.json()["access_token"]
    assert api_client.get(
        "/api/auth/me", HTTP_AUTHORIZATION=f"Bearer {token}"
    ).status_code == 200
