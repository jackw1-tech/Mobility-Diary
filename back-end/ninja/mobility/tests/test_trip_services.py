from datetime import timedelta

import pytest
from django.contrib.auth import get_user_model
from django.utils import timezone

from mobility.models import PartKind, SensorWindow, Trip, TripIngestion, TripIngestionPart
from mobility.services.trips import (
    TripServiceError,
    delete_trip,
    update_trip_note,
    update_trip_reloadable,
)


@pytest.fixture
def mobile_user(db):
    return get_user_model().objects.create_user(
        username="trip-service@example.com",
        email="trip-service@example.com",
        password="password-123",
    )


@pytest.fixture
def closed_trip(mobile_user):
    now = timezone.now()
    return Trip.objects.create(
        user=mobile_user,
        client_session_id="trip-service",
        status=Trip.Status.CLOSED,
        started_at=now - timedelta(minutes=30),
        ended_at=now,
    )


def _completed_ingestion(trip: Trip) -> TripIngestion:
    return TripIngestion.objects.create(
        user=trip.user,
        client_session_id=f"{trip.client_session_id}-ingestion",
        trip=trip,
        core_status=TripIngestion.PhaseStatus.COMPLETED,
        raw_status=TripIngestion.PhaseStatus.COMPLETED,
    )


@pytest.mark.django_db
def test_update_trip_note_requires_completed_ingestion(mobile_user, closed_trip):
    with pytest.raises(TripServiceError, match="nota disponibile"):
        update_trip_note(user_id=mobile_user.id, trip_id=closed_trip.id, note="hello")

    _completed_ingestion(closed_trip)

    item = update_trip_note(
        user_id=mobile_user.id,
        trip_id=closed_trip.id,
        note="  hello  ",
    )

    closed_trip.refresh_from_db()
    assert closed_trip.note == "hello"
    assert item["note"] == "hello"


@pytest.mark.django_db
def test_update_trip_reloadable_requires_raw_sensor_evidence(mobile_user, closed_trip):
    with pytest.raises(TripServiceError, match="telemetrie sorgente"):
        update_trip_reloadable(
            user_id=mobile_user.id,
            trip_id=closed_trip.id,
            is_reloadable=True,
        )

    ingestion = _completed_ingestion(closed_trip)
    TripIngestionPart.objects.create(
        ingestion=ingestion,
        kind=PartKind.SENSOR_WINDOWS,
        sequence=1,
        sha256="sensor-sha",
        size_bytes=10,
        object_key="sensor.bin.gz",
        received_at=timezone.now(),
    )

    item = update_trip_reloadable(
        user_id=mobile_user.id,
        trip_id=closed_trip.id,
        is_reloadable=True,
    )

    closed_trip.refresh_from_db()
    assert closed_trip.is_reloadable is True
    assert item["is_reloadable"] is True


@pytest.mark.django_db
def test_delete_trip_removes_storage_objects_and_database_rows(
    mobile_user,
    closed_trip,
    monkeypatch,
):
    ingestion = _completed_ingestion(closed_trip)
    SensorWindow.objects.create(
        trip=closed_trip,
        start_timestamp=closed_trip.started_at,
        end_timestamp=closed_trip.ended_at,
        sample_count=500,
        frequency_hz=100,
        object_key="window.bin",
    )
    TripIngestionPart.objects.create(
        ingestion=ingestion,
        kind=PartKind.SENSOR_WINDOWS,
        sequence=1,
        sha256="sensor-sha",
        size_bytes=10,
        object_key="part.bin",
        received_at=timezone.now(),
    )
    deleted_keys = []
    monkeypatch.setattr(
        "mobility.ingestion.storage.delete_object",
        lambda key: deleted_keys.append(key),
    )

    delete_trip(user_id=mobile_user.id, trip_id=closed_trip.id)

    assert deleted_keys == ["part.bin", "window.bin"]
    assert not Trip.objects.filter(id=closed_trip.id).exists()
    assert not TripIngestion.objects.filter(id=ingestion.id).exists()
