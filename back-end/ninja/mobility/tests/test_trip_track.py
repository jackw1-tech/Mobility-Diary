from datetime import timedelta

import pytest
from django.contrib.auth import get_user_model
from django.contrib.gis.geos import LineString, Point
from django.test import Client
from django.utils import timezone

from accounts.models import AccessToken
from mobility.models import (
    ActivityLabel,
    GpsPoint,
    MobilitySegment,
    PartKind,
    SignificantPlace,
    StateTransition,
    Trip,
    TripIngestion,
    TripIngestionPart,
)
from mobility.tasks import _build_trip_path, process_trip_ingestion


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


def create_trip(user, *, client_session_id="session-track") -> Trip:
    return Trip.objects.create(
        user=user,
        client_session_id=client_session_id,
        device_id="test-device",
        status=Trip.Status.CLOSED,
    )


def add_gps(trip: Trip, timestamp, lon: float, lat: float) -> GpsPoint:
    return GpsPoint.objects.create(
        trip=trip,
        timestamp=timestamp,
        point=Point(lon, lat, srid=4326),
        speed_mps=1.0,
    )


@pytest.mark.django_db
def test_build_trip_path_orders_points_by_timestamp(user):
    trip = create_trip(user)
    base = timezone.now()
    add_gps(trip, base + timedelta(minutes=2), 9.30, 45.46)
    add_gps(trip, base, 9.10, 45.46)
    add_gps(trip, base + timedelta(minutes=1), 9.20, 45.46)

    point_count = _build_trip_path(trip)

    trip.refresh_from_db()
    assert point_count == 3
    assert trip.path is not None
    assert trip.distance_meters > 0
    assert list(trip.path.coords) == [
        (9.10, 45.46),
        (9.20, 45.46),
        (9.30, 45.46),
    ]


@pytest.mark.django_db
@pytest.mark.parametrize("point_count", [0, 1])
def test_build_trip_path_keeps_path_empty_for_less_than_two_points(user, point_count):
    trip = create_trip(user, client_session_id=f"empty-{point_count}")
    if point_count:
        add_gps(trip, timezone.now(), 9.19, 45.46)

    returned_count = _build_trip_path(trip)

    trip.refresh_from_db()
    assert returned_count == point_count
    assert trip.path is None
    assert trip.distance_meters == 0


@pytest.mark.django_db
def test_process_trip_ingestion_builds_path_idempotently(monkeypatch, user):
    ingestion = TripIngestion.objects.create(
        user=user,
        client_session_id="ingestion-track",
        device_id="test-device",
        expected_core_parts={"gps_points": 1, "state_transitions": 1},
        expected_raw_parts={},
        raw_status=TripIngestion.PhaseStatus.COMPLETED,
    )
    now = timezone.now()
    TripIngestionPart.objects.create(
        ingestion=ingestion,
        kind=PartKind.GPS_POINTS,
        sequence=1,
        sha256="gps",
        object_key="gps.json.gz",
        received_at=now,
    )
    TripIngestionPart.objects.create(
        ingestion=ingestion,
        kind=PartKind.STATE_TRANSITIONS,
        sequence=1,
        sha256="state",
        object_key="state.json.gz",
        received_at=now,
    )

    def fake_load_json_gz(object_key):
        if object_key == "gps.json.gz":
            return {
                "points": [
                    {
                        "timestamp": (now + timedelta(minutes=2)).isoformat(),
                        "latitude": 45.46,
                        "longitude": 9.30,
                        "speed_mps": 1.0,
                    },
                    {
                        "timestamp": now.isoformat(),
                        "latitude": 45.46,
                        "longitude": 9.10,
                        "speed_mps": 1.0,
                    },
                ]
            }
        return {
            "transitions": [
                {
                    "timestamp": now.isoformat(),
                    "from_state": "STATIONARY",
                    "to_state": "ACTIVE_TRACKING",
                    "reason": "test",
                }
            ]
        }

    monkeypatch.setattr("mobility.tasks._load_json_gz", fake_load_json_gz)

    first_result = process_trip_ingestion.run(ingestion.id)
    second_result = process_trip_ingestion.run(ingestion.id)

    trip = Trip.objects.get(client_session_id="ingestion-track")
    assert first_result["path_points"] == 2
    assert second_result == {"skipped": "core ingestion already completed"}
    assert GpsPoint.objects.filter(trip=trip).count() == 2
    assert StateTransition.objects.filter(trip=trip).count() == 1
    assert trip.path is not None
    assert list(trip.path.coords) == [(9.10, 45.46), (9.30, 45.46)]


@pytest.mark.django_db
def test_track_endpoint_returns_geojson_distance_and_lon_lat_order(user):
    trip = create_trip(user)
    base = timezone.now()
    add_gps(trip, base, 9.10, 45.46)
    add_gps(trip, base + timedelta(minutes=1), 9.20, 45.47)
    _build_trip_path(trip)
    trip.refresh_from_db()

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/track",
        **auth_headers(user),
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["trip_id"] == trip.id
    assert payload["point_count"] == 2
    assert payload["distance_meters"] > 0
    assert payload["geojson"]["type"] == "LineString"
    assert payload["geojson"]["coordinates"][0] == [9.10, 45.46]
    assert payload["geojson"]["coordinates"][1] == [9.20, 45.47]


@pytest.mark.django_db
def test_track_endpoint_returns_404_for_other_user(user, other_user):
    trip = create_trip(user)
    add_gps(trip, timezone.now(), 9.10, 45.46)

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/track",
        **auth_headers(other_user),
    )

    assert response.status_code == 404


@pytest.mark.django_db
def test_track_endpoint_returns_empty_track_for_trip_without_path(user):
    trip = create_trip(user)
    add_gps(trip, timezone.now(), 9.10, 45.46)

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/track",
        **auth_headers(user),
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["trip_id"] == trip.id
    assert payload["point_count"] == 1
    assert payload["distance_meters"] == 0
    assert payload["geojson"] is None


@pytest.mark.django_db
def test_diary_endpoint_returns_not_yet_enriched_state(user):
    trip = create_trip(user)

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/diary",
        **auth_headers(user),
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["trip_id"] == trip.id
    assert payload["status"] == Trip.Status.CLOSED
    assert payload["processed"] is False
    assert payload["segments"] == []
    assert payload["places"] == []


@pytest.mark.django_db
def test_diary_endpoint_returns_segment_geometry_and_stop_place(user, other_user):
    trip = create_trip(user)
    trip.status = Trip.Status.PROCESSED
    trip.save(update_fields=["status", "updated_at"])
    base = timezone.now()
    place = SignificantPlace.objects.create(
        trip=trip,
        center=Point(9.20, 45.47, srid=4326),
        radius_meters=45,
        dwell_seconds=600,
        label="universita",
    )
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.MOVE,
        start_timestamp=base,
        end_timestamp=base + timedelta(minutes=10),
        activity_label=ActivityLabel.BIKING,
        path=LineString((9.10, 45.46), (9.20, 45.47), srid=4326),
        distance_meters=1200,
    )
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.STOP,
        start_timestamp=base + timedelta(minutes=10),
        end_timestamp=base + timedelta(minutes=20),
        activity_label=ActivityLabel.IDLE,
        place=place,
    )

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/diary",
        **auth_headers(user),
    )
    other_response = Client().get(
        f"/api/mobility/trips/{trip.id}/diary",
        **auth_headers(other_user),
    )

    assert response.status_code == 200
    assert other_response.status_code == 404
    payload = response.json()
    assert payload["processed"] is True
    assert len(payload["segments"]) == 2
    move, stop = payload["segments"]
    assert move["kind"] == MobilitySegment.Kind.MOVE
    assert move["activity_label"] == ActivityLabel.BIKING
    assert move["path_geojson"]["type"] == "LineString"
    assert move["path_geojson"]["coordinates"] == [[9.1, 45.46], [9.2, 45.47]]
    assert stop["kind"] == MobilitySegment.Kind.STOP
    assert stop["path_geojson"] is None
    assert stop["place"]["label"] == "universita"
