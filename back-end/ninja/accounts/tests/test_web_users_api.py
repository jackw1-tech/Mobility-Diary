import json
from datetime import timedelta

import pytest
from django.contrib.auth import get_user_model
from django.contrib.gis.geos import LineString, Point
from django.test import Client
from django.utils import timezone
from django.utils.dateparse import parse_datetime

from accounts.models import UserPrivacySettings
from mobility.models import (
    ActivityLabel,
    GpsPoint,
    HabitualPlace,
    MobilitySegment,
    Trip,
    VirtualStopInterval,
)
from mobility.privacy import PRIVACY_AWARE_STOP_LABEL, cloak_linestring


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


def _confirmed_place(user, lon, lat, **kwargs):
    return HabitualPlace.objects.create(
        user=user,
        center=Point(lon, lat, srid=4326),
        state=HabitualPlace.State.CONFIRMED,
        **kwargs,
    )


def _add_gps(trip, timestamp, lon, lat, *, speed=0.0):
    GpsPoint.objects.create(
        trip=trip,
        timestamp=timestamp,
        point=Point(lon, lat, srid=4326),
        speed_mps=speed,
    )


def _api_timestamp(value):
    return value.isoformat(timespec="milliseconds").replace("+00:00", "Z")


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
    assert parse_datetime(active_payload["latest_trip_started_at"]) == now.replace(
        microsecond=(now.microsecond // 1000) * 1000
    )
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
    _confirmed_place(owner, 9.2003, 45.4703, radius_meters=35, category="casa")
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
    )
    _add_gps(trip, base + timedelta(minutes=14), 9.2000, 45.4700)
    _add_gps(trip, base + timedelta(minutes=18), 9.2001, 45.4701)

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
    assert stop["place"]["label"] == "casa"
    assert stop["place"]["center_geojson"]["coordinates"] == pytest.approx(
        [9.20005, 45.47005]
    )


@pytest.mark.django_db
def test_web_trip_dashboard_returns_privacy_aware_geometry(staff_user):
    base = timezone.now()
    owner = create_user("privacy-dashboard-owner@example.com")
    UserPrivacySettings.objects.create(
        user=owner,
        level=UserPrivacySettings.Level.APPROXIMATE,
        is_first_login=False,
    )
    trip = make_trip(
        owner,
        status=Trip.Status.PROCESSED,
        started_at=base,
        ended_at=base + timedelta(minutes=30),
        distance_meters=1200,
        has_track=True,
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

    response = Client().get(
        f"/api/web/users/{owner.id}/trips/{trip.id}",
        **auth_headers(staff_user),
    )

    assert response.status_code == 200
    payload = response.json()
    privacy_aware = payload["privacy_aware"]
    assert privacy_aware["level"] == UserPrivacySettings.Level.APPROXIMATE
    assert privacy_aware["track"]["geojson"]["type"] == "LineString"
    assert privacy_aware["track"]["geojson"] != payload["track"]["geojson"]
    assert privacy_aware["track"]["geojson"]["coordinates"][0] != [9.1, 45.46]

    private_move = payload["diary"]["segments"][0]
    privacy_move = privacy_aware["diary"]["segments"][0]
    assert privacy_move["kind"] == private_move["kind"]
    assert privacy_move["start_timestamp"] == private_move["start_timestamp"]
    assert privacy_move["end_timestamp"] == private_move["end_timestamp"]
    assert privacy_move["activity_label"] == private_move["activity_label"]
    assert privacy_move["path_geojson"]["type"] == "LineString"
    assert privacy_move["path_geojson"] != private_move["path_geojson"]
    assert privacy_move["distance_meters"] != private_move["distance_meters"]
    assert privacy_move["distance_meters"] == pytest.approx(
        cloak_linestring(
            trip.segments.get(kind=MobilitySegment.Kind.MOVE).path,
            level=UserPrivacySettings.Level.APPROXIMATE,
        ).distance_meters
    )


@pytest.mark.django_db
def test_web_trip_dashboard_merges_consecutive_stop_and_idle_move(staff_user):
    base = timezone.now()
    owner = create_user("dashboard-merged-stop@example.com")
    trip = make_trip(
        owner,
        status=Trip.Status.PROCESSED,
        started_at=base,
        ended_at=base + timedelta(minutes=10),
        distance_meters=30,
        has_track=True,
    )
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.STOP,
        start_timestamp=base,
        end_timestamp=base + timedelta(minutes=5),
        activity_label=ActivityLabel.IDLE,
    )
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.MOVE,
        start_timestamp=base + timedelta(minutes=5),
        end_timestamp=base + timedelta(minutes=10),
        activity_label=ActivityLabel.IDLE,
        path=LineString((9.20, 45.47), (9.2001, 45.4701), srid=4326),
        distance_meters=30,
    )

    response = Client().get(
        f"/api/web/users/{owner.id}/trips/{trip.id}",
        **auth_headers(staff_user),
    )

    assert response.status_code == 200
    payload = response.json()
    assert len(payload["diary"]["segments"]) == 1
    stop = payload["diary"]["segments"][0]
    assert stop["kind"] == MobilitySegment.Kind.STOP
    assert stop["activity_label"] == ActivityLabel.IDLE
    assert stop["path_geojson"] is None
    assert stop["distance_meters"] == 0


@pytest.mark.django_db
def test_web_trip_dashboard_merges_adjacent_real_and_virtual_stop(staff_user):
    base = timezone.now()
    owner = create_user("dashboard-real-virtual-stop@example.com")
    trip = make_trip(
        owner,
        status=Trip.Status.PROCESSED,
        started_at=base,
        ended_at=base + timedelta(minutes=20),
        distance_meters=1100,
        has_track=True,
    )
    _confirmed_place(owner, 9.2003, 45.4703, radius_meters=35, category="casa")
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.MOVE,
        start_timestamp=base,
        end_timestamp=base + timedelta(minutes=5),
        activity_label=ActivityLabel.BIKING,
        path=LineString((9.10, 45.46), (9.15, 45.47), srid=4326),
        distance_meters=600,
    )
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.STOP,
        start_timestamp=base + timedelta(minutes=5),
        end_timestamp=base + timedelta(minutes=10),
        activity_label=ActivityLabel.IDLE,
    )
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.MOVE,
        start_timestamp=base + timedelta(minutes=15),
        end_timestamp=base + timedelta(minutes=20),
        activity_label=ActivityLabel.WALKING,
        path=LineString((9.15, 45.47), (9.20, 45.48), srid=4326),
        distance_meters=500,
    )
    VirtualStopInterval.objects.create(
        trip=trip,
        start_timestamp=base + timedelta(minutes=10),
        end_timestamp=base + timedelta(minutes=15),
    )
    _add_gps(trip, base + timedelta(minutes=7), 9.2000, 45.4700)
    _add_gps(trip, base + timedelta(minutes=12), 9.2001, 45.4701)

    response = Client().get(
        f"/api/web/users/{owner.id}/trips/{trip.id}",
        **auth_headers(staff_user),
    )

    assert response.status_code == 200
    payload = response.json()
    assert [
        (segment["kind"], segment["activity_label"])
        for segment in payload["diary"]["segments"]
    ] == [
        (MobilitySegment.Kind.MOVE, ActivityLabel.BIKING),
        (MobilitySegment.Kind.STOP, ActivityLabel.IDLE),
        (MobilitySegment.Kind.MOVE, ActivityLabel.WALKING),
    ]
    stop = payload["diary"]["segments"][1]
    assert stop["start_timestamp"] == _api_timestamp(base + timedelta(minutes=5))
    assert stop["end_timestamp"] == _api_timestamp(base + timedelta(minutes=15))
    assert stop["place"]["label"] == "casa"
    assert not any(
        segment["kind"] == MobilitySegment.Kind.MOVE
        and segment["activity_label"] == ActivityLabel.IDLE
        for segment in payload["diary"]["segments"]
    )


@pytest.mark.django_db
def test_web_trip_dashboard_defaults_to_saved_level_with_metrics_and_masked_places(
    staff_user,
):
    base = timezone.now()
    owner = create_user("privacy-metrics-owner@example.com")
    UserPrivacySettings.objects.create(
        user=owner,
        level=UserPrivacySettings.Level.APPROXIMATE,
        is_first_login=False,
    )
    trip = make_trip(
        owner,
        status=Trip.Status.PROCESSED,
        started_at=base,
        ended_at=base + timedelta(minutes=30),
        distance_meters=1200,
        has_track=True,
    )
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.STOP,
        start_timestamp=base + timedelta(minutes=10),
        end_timestamp=base + timedelta(minutes=20),
        activity_label=ActivityLabel.IDLE,
    )
    _confirmed_place(owner, 9.2003, 45.4703, radius_meters=35, category="casa")
    _add_gps(trip, base + timedelta(minutes=12), 9.2000, 45.4700)
    _add_gps(trip, base + timedelta(minutes=16), 9.2001, 45.4701)

    response = Client().get(
        f"/api/web/users/{owner.id}/trips/{trip.id}",
        **auth_headers(staff_user),
    )

    assert response.status_code == 200
    privacy = response.json()["privacy_aware"]
    assert privacy["level"] == UserPrivacySettings.Level.APPROXIMATE
    assert privacy["default_level"] == UserPrivacySettings.Level.APPROXIMATE

    perturbation = privacy["metrics"]["privacy_perturbation"]
    assert perturbation["sample_count"] == 2
    assert perturbation["mean_meters"] > 0
    assert perturbation["max_meters"] >= perturbation["mean_meters"]
    quality = privacy["metrics"]["quality_of_service"]
    assert quality["relative_distance_error"] >= 0
    assert quality["private_distance_meters"] > 0

    places = privacy["significant_places"]
    assert len(places) == 1
    assert places[0]["center_geojson"]["type"] == "Point"
    assert places[0]["center_geojson"]["coordinates"] != [9.2, 45.47]
    assert places[0]["label"] == PRIVACY_AWARE_STOP_LABEL
    stop = privacy["diary"]["segments"][0]
    assert stop["place"]["label"] == PRIVACY_AWARE_STOP_LABEL
    assert stop["place"]["center_geojson"]["coordinates"] != [9.2, 45.47]
    assert "casa" not in json.dumps(privacy)


@pytest.mark.django_db
def test_web_trip_dashboard_returns_generic_visible_stop_without_confirmed_place(
    staff_user,
):
    base = timezone.now()
    owner = create_user("generic-stop-owner@example.com")
    trip = make_trip(
        owner,
        status=Trip.Status.PROCESSED,
        started_at=base,
        ended_at=base + timedelta(minutes=20),
        distance_meters=400,
        has_track=True,
    )
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.STOP,
        start_timestamp=base + timedelta(minutes=5),
        end_timestamp=base + timedelta(minutes=15),
        activity_label=ActivityLabel.IDLE,
    )
    _add_gps(trip, base + timedelta(minutes=7), 9.2050, 45.4750)
    _add_gps(trip, base + timedelta(minutes=11), 9.2052, 45.4752)

    response = Client().get(
        f"/api/web/users/{owner.id}/trips/{trip.id}",
        **auth_headers(staff_user),
    )

    assert response.status_code == 200
    stop = response.json()["diary"]["segments"][0]
    assert stop["kind"] == MobilitySegment.Kind.STOP
    assert stop["place"]["label"] == "Sosta rilevata"
    assert stop["place"]["center_geojson"]["coordinates"] == pytest.approx(
        [9.2051, 45.4751]
    )


@pytest.mark.django_db
def test_web_trip_dashboard_preview_level_does_not_change_saved_preference(staff_user):
    base = timezone.now()
    owner = create_user("privacy-preview-owner@example.com")
    UserPrivacySettings.objects.create(
        user=owner,
        level=UserPrivacySettings.Level.PRECISE,
        is_first_login=False,
    )
    trip = make_trip(
        owner,
        status=Trip.Status.PROCESSED,
        started_at=base,
        distance_meters=1200,
        has_track=True,
    )

    response = Client().get(
        f"/api/web/users/{owner.id}/trips/{trip.id}",
        {"level": UserPrivacySettings.Level.AGGREGATED},
        **auth_headers(staff_user),
    )

    assert response.status_code == 200
    privacy = response.json()["privacy_aware"]
    assert privacy["level"] == UserPrivacySettings.Level.AGGREGATED
    assert privacy["default_level"] == UserPrivacySettings.Level.PRECISE
    assert privacy["track"]["geojson"]["coordinates"][0] != [9.1, 45.46]

    owner.refresh_from_db()
    assert owner.privacy_settings.level == UserPrivacySettings.Level.PRECISE


@pytest.mark.django_db
def test_web_trip_dashboard_precise_preview_is_unprotected(staff_user):
    base = timezone.now()
    owner = create_user("privacy-precise-owner@example.com")
    UserPrivacySettings.objects.create(
        user=owner,
        level=UserPrivacySettings.Level.AGGREGATED,
        is_first_login=False,
    )
    trip = make_trip(
        owner,
        status=Trip.Status.PROCESSED,
        started_at=base,
        distance_meters=1200,
        has_track=True,
    )
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.STOP,
        start_timestamp=base + timedelta(minutes=10),
        end_timestamp=base + timedelta(minutes=20),
        activity_label=ActivityLabel.IDLE,
    )
    _confirmed_place(owner, 9.2003, 45.4703, radius_meters=35, category="casa")
    _add_gps(trip, base + timedelta(minutes=12), 9.2000, 45.4700)
    _add_gps(trip, base + timedelta(minutes=16), 9.2001, 45.4701)

    response = Client().get(
        f"/api/web/users/{owner.id}/trips/{trip.id}",
        {"level": UserPrivacySettings.Level.PRECISE},
        **auth_headers(staff_user),
    )

    assert response.status_code == 200
    payload = response.json()
    privacy = payload["privacy_aware"]
    assert privacy["level"] == UserPrivacySettings.Level.PRECISE
    assert privacy["track"]["geojson"] == payload["track"]["geojson"]
    assert privacy["metrics"]["privacy_perturbation"]["max_meters"] == 0
    assert privacy["metrics"]["quality_of_service"]["relative_distance_error"] == 0
    place = privacy["significant_places"][0]
    assert place["label"] == "casa"
    assert place["center_geojson"]["coordinates"] == [9.2003, 45.4703]
    stop = privacy["diary"]["segments"][0]
    assert stop["place"]["label"] == "casa"
    assert stop["place"]["center_geojson"]["coordinates"] == pytest.approx(
        [9.20005, 45.47005]
    )


@pytest.mark.django_db
def test_web_trip_dashboard_rejects_invalid_privacy_level(staff_user):
    owner = create_user("privacy-invalid-owner@example.com")
    trip = make_trip(
        owner,
        status=Trip.Status.PROCESSED,
        started_at=timezone.now(),
        has_track=True,
    )

    response = Client().get(
        f"/api/web/users/{owner.id}/trips/{trip.id}",
        {"level": "blurred"},
        **auth_headers(staff_user),
    )

    assert response.status_code == 400


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
