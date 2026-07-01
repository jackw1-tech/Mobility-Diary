import gzip
import hashlib
import json
from datetime import datetime, timedelta
from datetime import timezone as dt_timezone

import pytest
from django.contrib.auth import get_user_model
from django.test import Client

from accounts.models import AccessToken
from mobility.models import PartKind, Trip, TripIngestion, TripIngestionPart

SOURCE_START = datetime(2026, 6, 12, 8, 0, 0, tzinfo=dt_timezone.utc)


@pytest.fixture
def user(db):
    return get_user_model().objects.create_user(
        username="assistant-replay@example.com",
        email="assistant-replay@example.com",
        password="password",
    )


def auth_headers(user):
    raw_token, _ = AccessToken.issue_for_user(user)
    return {"HTTP_AUTHORIZATION": f"Bearer {raw_token}"}


@pytest.fixture
def object_storage(monkeypatch):
    objects: dict[str, bytes] = {}
    monkeypatch.setattr("mobility.replay_raw.storage.read_object", objects.__getitem__)
    return objects


def make_source(user, *, reloadable: bool = True) -> Trip:
    return Trip.objects.create(
        user=user,
        client_session_id="src-session",
        device_id="src-device",
        status=Trip.Status.CLOSED,
        is_reloadable=reloadable,
        started_at=SOURCE_START,
        ended_at=SOURCE_START + timedelta(minutes=20),
    )


def add_window(trip: Trip, objects: dict, *, minute: int = 1, samples=None):
    samples = samples or [[1, 2, 3, 4, 5, 6], [7, 8, 9, 10, 11, 12]]
    body = {
        "windows": [
            {
                "window_start": (SOURCE_START + timedelta(minutes=minute))
                .isoformat()
                .replace("+00:00", "Z"),
                "window_end": (SOURCE_START + timedelta(minutes=minute, seconds=5))
                .isoformat()
                .replace("+00:00", "Z"),
                "sample_rate_hz": 100,
                "sample_count": len(samples),
                "samples": samples,
            }
        ]
    }
    raw = gzip.compress(json.dumps(body).encode("utf-8"))
    key = f"source/{trip.id}/sw.json.gz"
    objects[key] = raw
    ingestion = TripIngestion.objects.create(
        user=trip.user,
        client_session_id=f"src-ing-{trip.id}",
        device_id=trip.device_id,
        core_status=TripIngestion.PhaseStatus.COMPLETED,
        raw_status=TripIngestion.PhaseStatus.COMPLETED,
        trip=trip,
    )
    TripIngestionPart.objects.create(
        ingestion=ingestion,
        kind=PartKind.SENSOR_WINDOWS,
        sequence=1,
        sha256=hashlib.sha256(raw).hexdigest(),
        size_bytes=len(raw),
        object_key=key,
        received_at=SOURCE_START,
    )


def get_window(client, user, trip_id, offset_seconds):
    return client.get(
        f"/api/mobility/trips/reloadable/{trip_id}/sensor-window"
        f"?offset_seconds={offset_seconds}",
        **auth_headers(user),
    )


def test_returns_window_for_offset_inside_range(user, object_storage):
    # Finestra a 60-65s dall'inizio: offset 62 la centra.
    source = make_source(user)
    add_window(source, object_storage, minute=1)

    response = get_window(Client(), user, source.id, 62)

    assert response.status_code == 200
    assert response.json()["samples"] == [
        [1, 2, 3, 4, 5, 6],
        [7, 8, 9, 10, 11, 12],
    ]


def test_truncates_rows_to_six_channels(user, object_storage):
    source = make_source(user)
    add_window(
        source,
        object_storage,
        minute=1,
        samples=[[0, 1, 2, 3, 4, 5, 6, 7, 8]],
    )

    response = get_window(Client(), user, source.id, 62)

    assert response.status_code == 200
    assert response.json()["samples"] == [[0, 1, 2, 3, 4, 5]]


def test_offset_out_of_range_returns_404(user, object_storage):
    source = make_source(user)
    add_window(source, object_storage, minute=1)

    response = get_window(Client(), user, source.id, 99999)

    assert response.status_code == 404


def test_non_reloadable_returns_404(user, object_storage):
    source = make_source(user, reloadable=False)
    add_window(source, object_storage, minute=1)

    response = get_window(Client(), user, source.id, 62)

    assert response.status_code == 404


def test_requires_authentication(user, object_storage):
    source = make_source(user)
    add_window(source, object_storage, minute=1)

    response = Client().get(
        f"/api/mobility/trips/reloadable/{source.id}/sensor-window?offset_seconds=62"
    )

    assert response.status_code == 401
