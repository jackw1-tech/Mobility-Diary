import json

import jwt
import pytest
from django.conf import settings
from django.contrib.auth import get_user_model
from django.test import Client

from accounts.models import WebRefreshToken


def post_json(path: str, payload: dict):
    return Client().post(
        path,
        data=json.dumps(payload),
        content_type="application/json",
    )


def decode_token(token: str) -> dict:
    return jwt.decode(token, settings.SECRET_KEY, algorithms=["HS256"])


def login_staff() -> dict:
    return post_json(
        "/api/web/auth/login",
        {"email": "staff@example.com", "password": "password-123"},
    ).json()


@pytest.fixture
def staff_user(db):
    return get_user_model().objects.create_user(
        username="staff@example.com",
        email="staff@example.com",
        password="password-123",
        first_name="Ada",
        last_name="Staff",
        is_staff=True,
    )


@pytest.fixture
def mobile_user(db):
    return get_user_model().objects.create_user(
        username="mobile@example.com",
        email="mobile@example.com",
        password="password-123",
    )


@pytest.mark.django_db
def test_web_staff_login_issues_access_and_refresh_tokens(staff_user):
    response = post_json("/api/web/auth/login", {
        "email": "staff@example.com",
        "password": "password-123",
    })

    assert response.status_code == 200
    payload = response.json()
    assert payload["token_type"] == "Bearer"
    assert payload["user"]["email"] == "staff@example.com"
    assert payload["user"]["is_staff"] is True
    assert payload["access_token"]
    assert payload["refresh_token"]

    access_claims = decode_token(payload["access_token"])
    refresh_claims = decode_token(payload["refresh_token"])
    assert access_claims["type"] == "web_access"
    assert refresh_claims["type"] == "web_refresh"
    assert WebRefreshToken.objects.filter(
        jti=refresh_claims["jti"],
        user=staff_user,
        revoked_at__isnull=True,
    ).exists()


@pytest.mark.django_db
def test_web_login_rejects_non_staff_users(mobile_user):
    response = post_json(
        "/api/web/auth/login",
        {"email": "mobile@example.com", "password": "password-123"},
    )

    assert response.status_code == 403
    assert "staff" in response.json()["detail"].lower()
    assert WebRefreshToken.objects.count() == 0


@pytest.mark.django_db
def test_web_refresh_rotates_refresh_token(staff_user):
    login = login_staff()
    old_claims = decode_token(login["refresh_token"])

    response = post_json(
        "/api/web/auth/refresh",
        {"refresh_token": login["refresh_token"]},
    )

    assert response.status_code == 200
    payload = response.json()
    new_claims = decode_token(payload["refresh_token"])
    assert new_claims["jti"] != old_claims["jti"]

    old_refresh = WebRefreshToken.objects.get(jti=old_claims["jti"])
    assert old_refresh.revoked_at is not None
    assert old_refresh.rotated_to_jti == new_claims["jti"]
    assert WebRefreshToken.objects.filter(
        jti=new_claims["jti"],
        revoked_at__isnull=True,
    ).exists()

    reused = post_json(
        "/api/web/auth/refresh",
        {"refresh_token": login["refresh_token"]},
    )
    assert reused.status_code == 401


@pytest.mark.django_db
def test_web_logout_revokes_refresh_token(staff_user):
    login = login_staff()

    response = post_json(
        "/api/web/auth/logout",
        {"refresh_token": login["refresh_token"]},
    )

    assert response.status_code == 200
    claims = decode_token(login["refresh_token"])
    assert WebRefreshToken.objects.get(jti=claims["jti"]).revoked_at is not None

    refreshed = post_json(
        "/api/web/auth/refresh",
        {"refresh_token": login["refresh_token"]},
    )
    assert refreshed.status_code == 401


@pytest.mark.django_db
def test_web_me_requires_valid_staff_access_token(staff_user):
    login = login_staff()

    response = Client().get(
        "/api/web/auth/me",
        HTTP_AUTHORIZATION=f"Bearer {login['access_token']}",
    )

    assert response.status_code == 200
    assert response.json()["email"] == "staff@example.com"

    anonymous = Client().get("/api/web/auth/me")
    assert anonymous.status_code == 401
