import json
from datetime import timedelta

import pytest
from django.contrib.auth import get_user_model
from django.contrib.gis.geos import LineString, Point
from django.test import Client
from django.utils.dateparse import parse_datetime
from django.utils import timezone

from mobility.models import ActivityLabel, MobilitySegment, SignificantPlace, Trip


@pytest.fixture
def staff_user(db):
    return get_user_model().objects.create_user(
        username="staff@example.com",
        email="staff@example.com",
        password="password-123",
        is_staff=True,
    )


def web_access_token(staff_user) -> str:
    response = Client().post(
        "/api/web/auth/login",
        data=json.dumps(
            {
                "email": "staff@example.com",
                "password": "password-123",
            }
        ),
        content_type="application/json",
    )
    assert response.status_code == 200
    return response.json()["access_token"]


def auth_headers(staff_user) -> dict:
    return {"HTTP_AUTHORIZATION": f"Bearer {web_access_token(staff_user)}"}


def create_user(email: str, **flags):
    return get_user_model().objects.create_user(
        username=email,
        email=email,
        password="password-123",
        first_name=flags.pop("first_name", ""),
        last_name=flags.pop("last_name", ""),
        **flags,
    )


def make_trip(
    user,
    *,
    status: str,
    started_at,
    ended_at=None,
    distance_meters=None,
    has_track=False,
):
    trip = Trip.objects.create(
        user=user,
        client_session_id=f"{user.id}-{status}-{started_at.timestamp()}",
        device_id="test-device",
        status=status,
        ended_at=ended_at,
        distance_meters=distance_meters,
        path=LineString((9.10, 45.46), (9.20, 45.47), srid=4326)
        if has_track
        else None,
    )
    Trip.objects.filter(pk=trip.pk).update(started_at=started_at)
    return trip


@pytest.mark.django_db
def test_web_users_returns_non_staff_users_with_trip_summary(staff_user):
    now = timezone.now()
    active_owner = create_user(
        "active-owner@example.com",
        first_name="Active",
        last_name="Owner",
    )
    inactive_owner = create_user("inactive-owner@example.com", is_active=False)
    zero_trip_owner = create_user("zero-trip@example.com")
    create_user("operator@example.com", is_staff=True)
    create_user("root@example.com", is_staff=True, is_superuser=True)

    make_trip(
        active_owner,
        status=Trip.Status.PROCESSED,
        started_at=now - timedelta(days=1),
        distance_meters=1200,
    )
    make_trip(
        active_owner,
        status=Trip.Status.CLOSED,
        started_at=now,
        distance_meters=300,
    )
    make_trip(
        inactive_owner,
        status=Trip.Status.PROCESSED,
        started_at=now - timedelta(hours=2),
        distance_meters=None,
    )

    response = Client().get("/api/web/users", **auth_headers(staff_user))

    assert response.status_code == 200
    users_by_email = {item["email"]: item for item in response.json()}
    assert set(users_by_email) == {
        "active-owner@example.com",
        "inactive-owner@example.com",
        "zero-trip@example.com",
    }

    active_payload = users_by_email["active-owner@example.com"]
    assert active_payload["first_name"] == "Active"
    assert active_payload["last_name"] == "Owner"
    assert active_payload["is_active"] is True
    assert active_payload["trip_count"] == 2
    assert active_payload["processed_trip_count"] == 1
    assert parse_datetime(active_payload["latest_trip_started_at"]) == now
    assert active_payload["total_distance_meters"] == 1500

    inactive_payload = users_by_email["inactive-owner@example.com"]
    assert inactive_payload["is_active"] is False
    assert inactive_payload["trip_count"] == 1
    assert inactive_payload["processed_trip_count"] == 1
    assert inactive_payload["total_distance_meters"] == 0

    zero_payload = users_by_email["zero-trip@example.com"]
    assert zero_payload["trip_count"] == 0
    assert zero_payload["processed_trip_count"] == 0
    assert zero_payload["latest_trip_started_at"] is None
    assert zero_payload["total_distance_meters"] == 0


@pytest.mark.django_db
def test_web_users_requires_staff_access():
    response = Client().get("/api/web/users")
    assert response.status_code == 401


@pytest.mark.django_db
def test_web_user_trips_are_scoped_to_owner(staff_user):
    now = timezone.now()
    owner = create_user("owner@example.com", first_name="Trip", last_name="Owner")
    other_owner = create_user("other-owner@example.com")
    closed_track = make_trip(
        owner,
        status=Trip.Status.CLOSED,
        started_at=now - timedelta(days=2),
        ended_at=now - timedelta(days=2, hours=-1),
        distance_meters=800,
        has_track=True,
    )
    processed_track = make_trip(
        owner,
        status=Trip.Status.PROCESSED,
        started_at=now - timedelta(days=1),
        ended_at=now - timedelta(days=1, hours=-2),
        distance_meters=1800,
        has_track=True,
    )
    current_trip = make_trip(
        owner,
        status=Trip.Status.CLOSED,
        started_at=now,
        distance_meters=0,
        has_track=False,
    )
    make_trip(
        other_owner,
        status=Trip.Status.PROCESSED,
        started_at=now - timedelta(hours=1),
        distance_meters=9900,
        has_track=True,
    )

    response = Client().get(
        f"/api/web/users/{owner.id}/trips",
        **auth_headers(staff_user),
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["owner"]["email"] == "owner@example.com"
    assert payload["owner"]["trip_count"] == 3
    assert [trip["id"] for trip in payload["trips"]] == [
        current_trip.id,
        processed_track.id,
        closed_track.id,
    ]
    assert payload["trips"][0]["processed"] is False
    assert payload["trips"][0]["has_track"] is False
    assert payload["trips"][1]["processed"] is True
    assert payload["trips"][1]["has_track"] is True


@pytest.mark.django_db
def test_web_user_trips_support_each_filter(staff_user):
    now = timezone.now()
    owner = create_user("filtered-owner@example.com")
    older = make_trip(
        owner,
        status=Trip.Status.CLOSED,
        started_at=now - timedelta(days=3),
        has_track=False,
    )
    tracked = make_trip(
        owner,
        status=Trip.Status.CLOSED,
        started_at=now - timedelta(days=2),
        has_track=True,
    )
    processed = make_trip(
        owner,
        status=Trip.Status.PROCESSED,
        started_at=now - timedelta(days=1),
        has_track=True,
    )

    expectations = [
        (
            {"from": (now - timedelta(days=1, hours=1)).isoformat()},
            [processed.id],
        ),
        (
            {"to": (now - timedelta(days=2, hours=12)).isoformat()},
            [older.id],
        ),
        ({"status": Trip.Status.CLOSED}, [tracked.id, older.id]),
        ({"processed": "true"}, [processed.id]),
        ({"processed": "false"}, [tracked.id, older.id]),
        ({"has_track": "true"}, [processed.id, tracked.id]),
        ({"has_track": "false"}, [older.id]),
    ]
    headers = auth_headers(staff_user)

    for query, expected_ids in expectations:
        response = Client().get(f"/api/web/users/{owner.id}/trips", query, **headers)

        assert response.status_code == 200
        assert [trip["id"] for trip in response.json()["trips"]] == expected_ids


@pytest.mark.django_db
def test_web_user_trips_requires_staff_access():
    owner = create_user("owner@example.com")

    response = Client().get(f"/api/web/users/{owner.id}/trips")

    assert response.status_code == 401


@pytest.mark.django_db
def test_web_trip_dashboard_returns_track_and_diary_for_staff(staff_user):
    base = timezone.now()
    owner = create_user("dashboard-owner@example.com", first_name="Dash")
    trip = make_trip(
        owner,
        status=Trip.Status.PROCESSED,
        started_at=base,
        ended_at=base + timedelta(minutes=30),
        distance_meters=1200,
        has_track=True,
    )
    place = SignificantPlace.objects.create(
        trip=trip,
        center=Point(9.20, 45.47, srid=4326),
        radius_meters=35,
        dwell_seconds=600,
        label="casa",
    )
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.MOVE,
        start_timestamp=base,
        end_timestamp=base + timedelta(minutes=12),
        activity_label=ActivityLabel.WALKING,
        path=LineString((9.10, 45.46), (9.20, 45.47), srid=4326),
        distance_meters=900,
    )
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.STOP,
        start_timestamp=base + timedelta(minutes=12),
        end_timestamp=base + timedelta(minutes=22),
        activity_label=ActivityLabel.IDLE,
        place=place,
    )

    response = Client().get(
        f"/api/web/users/{owner.id}/trips/{trip.id}",
        **auth_headers(staff_user),
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["owner"]["email"] == "dashboard-owner@example.com"
    assert payload["trip"]["id"] == trip.id
    assert payload["track"]["geojson"]["type"] == "LineString"
    assert payload["track"]["geojson"]["coordinates"][0] == [9.1, 45.46]
    assert payload["diary"]["processed"] is True
    assert len(payload["diary"]["segments"]) == 2
    move, stop = payload["diary"]["segments"]
    assert move["kind"] == MobilitySegment.Kind.MOVE
    assert move["activity_label"] == ActivityLabel.WALKING
    assert move["path_geojson"]["type"] == "LineString"
    assert stop["kind"] == MobilitySegment.Kind.STOP
    assert stop["path_geojson"] is None
    assert "place" not in stop
    assert "places" not in payload["diary"]


@pytest.mark.django_db
def test_web_trip_dashboard_requires_staff_access():
    owner = create_user("dashboard-owner@example.com")
    trip = make_trip(
        owner,
        status=Trip.Status.CLOSED,
        started_at=timezone.now(),
    )

    response = Client().get(f"/api/web/users/{owner.id}/trips/{trip.id}")

    assert response.status_code == 401
