from datetime import timedelta

import pytest
from django.contrib.auth import get_user_model
from django.contrib.gis.geos import Point
from django.test import Client
from django.utils import timezone

from accounts.models import AccessToken
from mobility.models import GpsPoint, Trip, TripIngestion
from mobility.tasks import _build_trip_path


@pytest.fixture
def user(db):
    return get_user_model().objects.create_user(
        username="owner@example.com",
        email="owner@example.com",
        password="password",
    )


@pytest.fixture
def other_user(db):
    return get_user_model().objects.create_user(
        username="other@example.com",
        email="other@example.com",
        password="password",
    )


def auth_headers(user):
    raw_token, _ = AccessToken.issue_for_user(user)
    return {"HTTP_AUTHORIZATION": f"Bearer {raw_token}"}


def make_trip(user, *, client_session_id, started_at) -> Trip:
    trip = Trip.objects.create(
        user=user,
        client_session_id=client_session_id,
        device_id="test-device",
        status=Trip.Status.CLOSED,
    )
    # started_at e' auto_now_add: lo forzo per testare l'ordinamento.
    Trip.objects.filter(pk=trip.pk).update(started_at=started_at)
    trip.refresh_from_db()
    return trip


@pytest.mark.django_db
def test_list_trips_returns_user_trips_newest_first_with_track_flag(user):
    now = timezone.now()
    older = make_trip(user, client_session_id="a", started_at=now - timedelta(hours=2))
    newer = make_trip(user, client_session_id="b", started_at=now)

    # Solo "newer" ha una traiettoria disegnabile.
    GpsPoint.objects.create(
        trip=newer, timestamp=now, point=Point(9.1, 45.4, srid=4326), speed_mps=1.0
    )
    GpsPoint.objects.create(
        trip=newer,
        timestamp=now + timedelta(minutes=1),
        point=Point(9.2, 45.5, srid=4326),
        speed_mps=1.0,
    )
    _build_trip_path(newer)

    response = Client().get("/api/mobility/trips", **auth_headers(user))

    assert response.status_code == 200
    payload = response.json()
    assert [t["id"] for t in payload] == [newer.id, older.id]
    assert payload[0]["has_track"] is True
    assert payload[0]["distance_meters"] > 0
    assert payload[1]["has_track"] is False


@pytest.mark.django_db
def test_list_trips_excludes_other_users_trips(user, other_user):
    make_trip(user, client_session_id="mine", started_at=timezone.now())
    make_trip(other_user, client_session_id="theirs", started_at=timezone.now())

    response = Client().get("/api/mobility/trips", **auth_headers(user))

    assert response.status_code == 200
    payload = response.json()
    assert len(payload) == 1
    assert payload[0]["status"] == Trip.Status.CLOSED


@pytest.mark.django_db
def test_list_trips_ignores_abandoned_ingestions_without_visible_trip(user):
    now = timezone.now()
    visible = make_trip(user, client_session_id="visible", started_at=now)
    TripIngestion.objects.create(
        user=user,
        client_session_id="abandoned-recording",
        device_id="test-device",
        recording_started_at=now - timedelta(minutes=10),
        recording_abandoned_at=now,
    )

    response = Client().get("/api/mobility/trips", **auth_headers(user))

    assert response.status_code == 200
    assert [trip["id"] for trip in response.json()] == [visible.id]


@pytest.mark.django_db
def test_list_trips_requires_auth():
    response = Client().get("/api/mobility/trips")
    assert response.status_code == 401
