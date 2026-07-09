from datetime import timedelta

import pytest
from django.contrib.auth import get_user_model
from django.contrib.gis.geos import Point
from django.utils import timezone

from mobility.ingestion.materialization import build_trip_path
from mobility.models import GpsPoint, Trip
from mobility.selectors.trips import trip_list_items_for_user, trip_track_for_user


@pytest.fixture
def users(db):
    model = get_user_model()
    return (
        model.objects.create_user(
            username="trip-owner@example.com",
            email="trip-owner@example.com",
            password="password-123",
        ),
        model.objects.create_user(
            username="trip-other@example.com",
            email="trip-other@example.com",
            password="password-123",
        ),
    )


@pytest.mark.django_db
def test_trip_list_items_for_user_returns_owned_trips_ordered_with_track_flags(users):
    owner, other = users
    now = timezone.now()
    older = Trip.objects.create(
        user=owner,
        client_session_id="older",
        status=Trip.Status.CLOSED,
        started_at=now - timedelta(hours=2),
        ended_at=now - timedelta(hours=1, minutes=30),
    )
    newer = Trip.objects.create(
        user=owner,
        client_session_id="newer",
        status=Trip.Status.CLOSED,
        started_at=now - timedelta(minutes=30),
        ended_at=now,
    )
    Trip.objects.create(
        user=other,
        client_session_id="other",
        status=Trip.Status.CLOSED,
        started_at=now,
        ended_at=now,
    )
    GpsPoint.objects.bulk_create(
        [
            GpsPoint(
                trip=newer,
                timestamp=now - timedelta(minutes=20),
                point=Point(9.19, 45.4642, srid=4326),
                speed_mps=1,
            ),
            GpsPoint(
                trip=newer,
                timestamp=now - timedelta(minutes=10),
                point=Point(9.2, 45.465, srid=4326),
                speed_mps=1,
            ),
        ]
    )
    build_trip_path(newer)

    rows = trip_list_items_for_user(owner.id)

    assert [row["id"] for row in rows] == [newer.id, older.id]
    assert rows[0]["has_track"] is True
    assert rows[1]["has_track"] is False


@pytest.mark.django_db
def test_trip_track_for_user_returns_track_payload_or_none(users):
    owner, other = users
    now = timezone.now()
    trip = Trip.objects.create(
        user=owner,
        client_session_id="track",
        status=Trip.Status.CLOSED,
        started_at=now - timedelta(minutes=30),
        ended_at=now,
    )
    GpsPoint.objects.bulk_create(
        [
            GpsPoint(
                trip=trip,
                timestamp=now - timedelta(minutes=20),
                point=Point(9.19, 45.4642, srid=4326),
                speed_mps=1,
            ),
            GpsPoint(
                trip=trip,
                timestamp=now - timedelta(minutes=10),
                point=Point(9.2, 45.465, srid=4326),
                speed_mps=1,
            ),
        ]
    )
    build_trip_path(trip)
    no_track = Trip.objects.create(
        user=owner,
        client_session_id="no-track",
        status=Trip.Status.CLOSED,
        started_at=now - timedelta(hours=2),
        ended_at=now - timedelta(hours=1),
    )

    track = trip_track_for_user(trip.id, owner.id)
    empty_track = trip_track_for_user(no_track.id, owner.id)

    assert track is not None
    assert track["trip_id"] == trip.id
    assert track["point_count"] == 2
    assert track["distance_meters"] > 0
    assert track["geojson"]["type"] == "LineString"
    assert empty_track is not None
    assert empty_track["geojson"] is None
    assert trip_track_for_user(trip.id, other.id) is None
