import json

import pytest
from django.contrib.auth import get_user_model
from django.test import Client

from accounts.models import UserPrivacySettings


@pytest.mark.django_db
def test_register_creates_default_privacy_settings():
    response = Client().post(
        "/api/auth/register",
        data=json.dumps(
            {
                "email": "new-user@example.com",
                "password": "a-strong-password-123",
                "first_name": "New",
                "last_name": "User",
            }
        ),
        content_type="application/json",
    )

    assert response.status_code == 201

    user = get_user_model().objects.get(email="new-user@example.com")
    settings = UserPrivacySettings.objects.get(user=user)
    assert settings.is_first_login is True
    assert settings.level == UserPrivacySettings.Level.PRECISE
