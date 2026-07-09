from datetime import datetime, timedelta, timezone as dt_timezone

import pytest
from django.contrib.auth import get_user_model
from django.contrib.gis.geos import Point

from mobility.models import (
    GpsPoint,
    PartKind,
    StateTransition,
    Trip,
    TripIngestion,
    TripIngestionPart,
)
from mobility.services.reload import reload_slots_for_trip, reload_trip_from_source


@pytest.fixture
def mobile_user(db):
    return get_user_model().objects.create_user(
        username="reload-service@example.com",
        email="reload-service@example.com",
        password="password-123",
    )


@pytest.fixture
def reloadable_source(mobile_user):
    start = datetime(2026, 1, 1, 8, tzinfo=dt_timezone.utc)
    trip = Trip.objects.create(
        user=mobile_user,
        client_session_id="source-trip",
        device_id="device-1",
        status=Trip.Status.PROCESSED,
        is_reloadable=True,
        started_at=start,
        ended_at=start + timedelta(minutes=30),
    )
    GpsPoint.objects.bulk_create(
        [
            GpsPoint(
                trip=trip,
                timestamp=start,
                point=Point(9.19, 45.4642, srid=4326),
                speed_mps=1,
                accuracy_meters=5,
            ),
            GpsPoint(
                trip=trip,
                timestamp=start + timedelta(minutes=20),
                point=Point(9.2, 45.465, srid=4326),
                speed_mps=1,
                accuracy_meters=5,
            ),
        ]
    )
    StateTransition.objects.create(
        trip=trip,
        timestamp=start + timedelta(minutes=1),
        from_state="STATIONARY",
        to_state="MOVEMENT",
        reason="test",
        sigma=0.1,
        speed_mps=1,
    )
    ingestion = TripIngestion.objects.create(
        user=mobile_user,
        client_session_id="source-ingestion",
        trip=trip,
        core_status=TripIngestion.PhaseStatus.COMPLETED,
        raw_status=TripIngestion.PhaseStatus.COMPLETED,
    )
    TripIngestionPart.objects.create(
        ingestion=ingestion,
        kind=PartKind.SENSOR_WINDOWS,
        sequence=1,
        sha256="sensor-sha",
        size_bytes=10,
        object_key="source-sensor.json.gz",
        received_at=start,
    )
    return trip


@pytest.mark.django_db
def test_reload_slots_for_trip_returns_available_slots(mobile_user, reloadable_source):
    now = datetime(2026, 1, 2, 12, tzinfo=dt_timezone.utc)

    result = reload_slots_for_trip(
        user_id=mobile_user.id,
        trip_id=reloadable_source.id,
        days=1,
        step_minutes=30,
        limit=3,
        now=now,
    )

    assert result["source_trip_id"] == reloadable_source.id
    assert result["duration_seconds"] == 30 * 60
    assert len(result["slots"]) == 3
    assert all(slot["ended_at"] <= now for slot in result["slots"])


@pytest.mark.django_db
def test_reload_trip_from_source_materializes_shifted_trip_and_is_idempotent(
    mobile_user,
    reloadable_source,
    monkeypatch,
):
    now = datetime(2026, 1, 2, 12, tzinfo=dt_timezone.utc)
    queued = []

    def fake_regenerate_raw_and_queue_har(ingestion, source, *, shift, now, cutoff=None):
        queued.append((ingestion.id, source.id, shift, now, cutoff))
        ingestion.raw_status = TripIngestion.PhaseStatus.QUEUED
        ingestion.save(update_fields=["raw_status", "updated_at"])

    monkeypatch.setattr(
        "mobility.services.reload.regenerate_raw_and_queue_har",
        fake_regenerate_raw_and_queue_har,
    )

    first = reload_trip_from_source(
        user_id=mobile_user.id,
        trip_id=reloadable_source.id,
        reload_request_id="request-1",
        scheduled_start_at=None,
        now=now,
    )
    second = reload_trip_from_source(
        user_id=mobile_user.id,
        trip_id=reloadable_source.id,
        reload_request_id="request-1",
        scheduled_start_at=None,
        now=now,
    )

    trip = Trip.objects.get(id=first["trip_id"])
    assert first == second
    assert len(queued) == 1
    assert first["gps_points"] == 2
    assert first["state_transitions"] == 1
    assert first["path_points"] == 2
    assert first["map_available"] is True
    assert trip.reloaded_from_trip_id == reloadable_source.id
    assert trip.started_at == now - timedelta(minutes=30)
