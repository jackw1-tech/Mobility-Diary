import json

import pytest
from django.contrib.auth import get_user_model
from django.test import Client

from accounts.models import AccessToken, UserPrivacySettings


@pytest.fixture
def user(db):
    return get_user_model().objects.create_user(
        username="privacy-owner@example.com",
        email="privacy-owner@example.com",
        password="password",
    )


@pytest.fixture
def other_user(db):
    return get_user_model().objects.create_user(
        username="privacy-other@example.com",
        email="privacy-other@example.com",
        password="password",
    )


def auth_headers(user):
    raw_token, _ = AccessToken.issue_for_user(user)
    return {"HTTP_AUTHORIZATION": f"Bearer {raw_token}"}


@pytest.mark.django_db
def test_privacy_settings_default_to_precise(user):
    response = Client().get("/api/privacy/settings", **auth_headers(user))

    assert response.status_code == 200
    assert response.json() == {"privacy_level": "precise", "is_first_login": True}
    assert user.privacy_settings.level == UserPrivacySettings.Level.PRECISE


@pytest.mark.django_db
@pytest.mark.parametrize("level", ["precise", "approximate", "aggregated"])
def test_privacy_settings_update_allowed_levels(user, level):
    response = Client().put(
        "/api/privacy/settings",
        data=json.dumps({"privacy_level": level}),
        content_type="application/json",
        **auth_headers(user),
    )

    assert response.status_code == 200
    assert response.json() == {"privacy_level": level, "is_first_login": False}
    assert user.privacy_settings.level == level


@pytest.mark.django_db
def test_privacy_settings_update_clears_first_login_flag(user):
    assert UserPrivacySettings.objects.get(user=user).is_first_login is True

    Client().put(
        "/api/privacy/settings",
        data=json.dumps({"privacy_level": "approximate"}),
        content_type="application/json",
        **auth_headers(user),
    )

    user.privacy_settings.refresh_from_db()
    assert user.privacy_settings.is_first_login is False


@pytest.mark.django_db
def test_privacy_settings_reject_invalid_level(user):
    response = Client().put(
        "/api/privacy/settings",
        data=json.dumps({"privacy_level": "public"}),
        content_type="application/json",
        **auth_headers(user),
    )

    assert response.status_code == 400
    assert not UserPrivacySettings.objects.filter(user=user).exists()


@pytest.mark.django_db
def test_privacy_settings_are_isolated_per_user(user, other_user):
    client = Client()
    client.put(
        "/api/privacy/settings",
        data=json.dumps({"privacy_level": "aggregated"}),
        content_type="application/json",
        **auth_headers(user),
    )

    response = client.get("/api/privacy/settings", **auth_headers(other_user))

    assert response.status_code == 200
    assert response.json() == {"privacy_level": "precise", "is_first_login": True}
    assert user.privacy_settings.level == "aggregated"
    assert other_user.privacy_settings.level == "precise"
