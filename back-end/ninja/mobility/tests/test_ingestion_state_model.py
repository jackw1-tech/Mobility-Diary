import pytest
from django.contrib.auth import get_user_model
from django.contrib.gis.geos import LineString
from django.test import Client

from accounts.models import AccessToken
from mobility.models import Trip, TripIngestion


@pytest.fixture
def user(db):
    return get_user_model().objects.create_user(
        username="owner-ingestion@example.com",
        email="owner-ingestion@example.com",
        password="password",
    )


@pytest.fixture
def other_user(db):
    return get_user_model().objects.create_user(
        username="other-ingestion@example.com",
        email="other-ingestion@example.com",
        password="password",
    )


def auth_headers(user):
    raw_token, _ = AccessToken.issue_for_user(user)
    return {"HTTP_AUTHORIZATION": f"Bearer {raw_token}"}


@pytest.mark.django_db
def test_trip_ingestion_core_inline_state_defaults(user):
    ingestion = TripIngestion.objects.create(
        user=user,
        client_session_id="core-defaults",
    )

    assert ingestion.core_ingestion_mode == TripIngestion.CoreIngestionMode.LEGACY_PARTS
    assert ingestion.core_payload_sha256 == ""
    assert ingestion.core_payload_size_bytes == 0


@pytest.mark.django_db
def test_ingestion_status_exposes_core_mode_and_map_availability(user):
    trip = Trip.objects.create(
        user=user,
        client_session_id="core-inline-trip",
        device_id="test-device",
        status=Trip.Status.PROCESSED,
        path=LineString((9.10, 45.46), (9.20, 45.47), srid=4326),
        distance_meters=1200,
    )
    ingestion = TripIngestion.objects.create(
        user=user,
        client_session_id="core-inline-trip",
        core_status=TripIngestion.PhaseStatus.COMPLETED,
        raw_status=TripIngestion.PhaseStatus.PENDING,
        core_ingestion_mode=TripIngestion.CoreIngestionMode.INLINE,
        core_payload_sha256="a" * 64,
        core_payload_size_bytes=512,
        trip=trip,
    )

    response = Client().get(
        f"/api/ingestion/trips/{ingestion.id}",
        **auth_headers(user),
    )

    assert response.status_code == 200
    data = response.json()
    assert data["core_ingestion_mode"] == TripIngestion.CoreIngestionMode.INLINE
    assert data["trip_id"] == trip.id
    assert data["map_available"] is True


@pytest.mark.django_db
def test_ingestion_status_hides_other_users_ingestion(user, other_user):
    ingestion = TripIngestion.objects.create(
        user=other_user,
        client_session_id="not-mine",
    )

    response = Client().get(
        f"/api/ingestion/trips/{ingestion.id}",
        **auth_headers(user),
    )

    assert response.status_code == 404


@pytest.mark.django_db
def test_ingestion_status_requires_materialized_path_for_map(user):
    trip = Trip.objects.create(
        user=user,
        client_session_id="core-no-path",
        device_id="test-device",
        status=Trip.Status.PROCESSED,
    )
    ingestion = TripIngestion.objects.create(
        user=user,
        client_session_id="core-no-path",
        core_status=TripIngestion.PhaseStatus.COMPLETED,
        raw_status=TripIngestion.PhaseStatus.COMPLETED,
        core_ingestion_mode=TripIngestion.CoreIngestionMode.INLINE,
        trip=trip,
    )

    response = Client().get(
        f"/api/ingestion/trips/{ingestion.id}",
        **auth_headers(user),
    )

    assert response.status_code == 200
    assert response.json()["map_available"] is False
