import json

import pytest
from django.test import Client


TEST_PASSWORD = "Mobility-diary-2026!"


@pytest.fixture
def api_client():
    return Client(HTTP_HOST="localhost")


@pytest.fixture
def register_mobile_user(api_client):
    def register(
        email: str = "mario.rossi@example.com",
        *,
        password: str = TEST_PASSWORD,
        first_name: str = "Mario",
        last_name: str = "Rossi",
    ):
        response = api_client.post(
            "/api/auth/register",
            data=json.dumps(
                {
                    "email": email,
                    "password": password,
                    "first_name": first_name,
                    "last_name": last_name,
                }
            ),
            content_type="application/json",
        )
        return response

    return register


@pytest.fixture
def mobile_session(register_mobile_user):
    response = register_mobile_user()
    assert response.status_code == 201, response.content
    payload = response.json()
    return {
        "token": payload["access_token"],
        "user": payload["user"],
        "headers": {"HTTP_AUTHORIZATION": f"Bearer {payload['access_token']}"},
    }
