import json

import pytest
from django.conf import settings
from django.contrib.auth import get_user_model
from django.test import Client

from accounts.models import AccessToken
from mobility import api as mobility_api


@pytest.fixture
def user(db):
    return get_user_model().objects.create_user(
        username="assistant-owner@example.com",
        email="assistant-owner@example.com",
        password="password",
    )


def auth_headers(user):
    raw_token, _ = AccessToken.issue_for_user(user)
    return {"HTTP_AUTHORIZATION": f"Bearer {raw_token}"}


def window(rows: int | None = None, cols: int = 6) -> list[list[float]]:
    rows = rows if rows is not None else settings.HAR_WINDOW_SAMPLE_COUNT
    return [[float(c) for c in range(cols)] for _ in range(rows)]


def classify(client: Client, user, samples: list[list[float]]):
    return client.post(
        "/api/mobility/route-assistant/classify",
        data=json.dumps({"samples": samples}),
        content_type="application/json",
        **auth_headers(user),
    )


def test_classify_returns_mapped_label_and_confidence(user, monkeypatch):
    # MOVING_VEHICLE deve essere esposto come "driving".
    monkeypatch.setattr(
        mobility_api, "predict_window_label", lambda samples: ("MOVING_VEHICLE", 0.87)
    )

    response = classify(Client(), user, window())

    assert response.status_code == 200
    assert response.json() == {"label": "driving", "confidence": 0.87}


def test_classify_maps_running_to_walking(user, monkeypatch):
    monkeypatch.setattr(
        mobility_api, "predict_window_label", lambda samples: ("RUNNING", 0.5)
    )

    response = classify(Client(), user, window())

    assert response.status_code == 200
    assert response.json()["label"] == "walking"


def test_classify_rejects_wrong_sample_count(user, monkeypatch):
    monkeypatch.setattr(
        mobility_api,
        "predict_window_label",
        lambda samples: pytest.fail("non deve classificare payload invalido"),
    )

    response = classify(Client(), user, window(rows=settings.HAR_WINDOW_SAMPLE_COUNT - 1))

    assert response.status_code == 422


def test_classify_rejects_rows_with_too_few_channels(user):
    response = classify(Client(), user, window(cols=5))

    assert response.status_code == 422


def test_classify_requires_authentication(db):
    response = Client().post(
        "/api/mobility/route-assistant/classify",
        data=json.dumps({"samples": window()}),
        content_type="application/json",
    )

    assert response.status_code == 401
