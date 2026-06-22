import gzip
import json
from datetime import timedelta

import pytest
from django.contrib.auth import get_user_model
from django.contrib.gis.geos import Point
from django.test import Client
from django.utils import timezone

from accounts.models import AccessToken
from mobility.ingestion import storage
from mobility.models import (
    ActivityLabel,
    GpsPoint,
    HarJob,
    MobilitySegment,
    PartKind,
    StateTransition,
    Trip,
    TripIngestion,
    TripIngestionPart,
)
from mobility.tasks import process_trip_har_final


@pytest.fixture
def user(db):
    return get_user_model().objects.create_user(
        username="har-owner@example.com",
        email="har-owner@example.com",
        password="password",
    )


def auth_headers(user):
    raw_token, _ = AccessToken.issue_for_user(user)
    return {"HTTP_AUTHORIZATION": f"Bearer {raw_token}"}


def stable_json(data: dict) -> bytes:
    return json.dumps(
        data,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode("utf-8")


def _sensor_part_payload(start):
    matrix = [[0.0, 0.1, 9.8, 0.01, 0.02, 0.03, 1.0, 2.0, 3.0] for _ in range(500)]
    return {
        "windows": [
            {
                "window_start": start.isoformat(),
                "window_end": (start + timedelta(minutes=5)).isoformat(),
                "sample_rate_hz": 100,
                "sample_count": 500,
                "samples": matrix,
            },
            {
                "window_start": (start + timedelta(minutes=5)).isoformat(),
                "window_end": (start + timedelta(minutes=10)).isoformat(),
                "sample_rate_hz": 100,
                "sample_count": 500,
                "samples": matrix,
            },
        ]
    }


def _create_har_ingestion(user, *, session_id: str, start):
    trip = Trip.objects.create(
        user=user,
        client_session_id=session_id,
        device_id="test-device",
        status=Trip.Status.CLOSED,
        ended_at=start + timedelta(minutes=15),
    )
    ingestion = TripIngestion.objects.create(
        user=user,
        client_session_id=session_id,
        core_status=TripIngestion.PhaseStatus.COMPLETED,
        raw_status=TripIngestion.PhaseStatus.QUEUED,
        expected_raw_parts={PartKind.SENSOR_WINDOWS: 1},
        trip=trip,
    )
    TripIngestionPart.objects.create(
        ingestion=ingestion,
        kind=PartKind.SENSOR_WINDOWS,
        sequence=1,
        sha256="a" * 64,
        object_key="sensor_windows_part_0001.json.gz",
        received_at=timezone.now(),
    )
    return trip, ingestion, HarJob.objects.create(
        trip=trip,
        kind=HarJob.Kind.FINAL_TRIP,
    )


@pytest.mark.django_db
def test_complete_raw_queues_har_final_after_all_raw_parts(
    user,
    monkeypatch,
    django_capture_on_commit_callbacks,
):
    delayed: list[tuple[int, int]] = []
    trip = Trip.objects.create(
        user=user,
        client_session_id="har-queue",
        device_id="test-device",
        status=Trip.Status.CLOSED,
    )
    ingestion = TripIngestion.objects.create(
        user=user,
        client_session_id="har-queue",
        core_status=TripIngestion.PhaseStatus.COMPLETED,
        raw_status=TripIngestion.PhaseStatus.RECEIVED,
        expected_raw_parts={PartKind.SENSOR_WINDOWS: 1},
        trip=trip,
    )
    TripIngestionPart.objects.create(
        ingestion=ingestion,
        kind=PartKind.SENSOR_WINDOWS,
        sequence=1,
        sha256="a" * 64,
        size_bytes=10,
        object_key="sensor_windows_part_0001.json.gz",
        received_at=timezone.now(),
    )

    monkeypatch.setattr(
        process_trip_har_final,
        "delay",
        lambda job_id, ingestion_id: delayed.append((job_id, ingestion_id)),
    )

    with django_capture_on_commit_callbacks(execute=True) as callbacks:
        response = Client().post(
            f"/api/ingestion/trips/{ingestion.id}/complete-raw",
            data=stable_json({"manifest_sha256": "b" * 64, "total_parts": 1}).decode(
                "utf-8"
            ),
            content_type="application/json",
            **auth_headers(user),
        )

    assert response.status_code == 202, response.content
    assert response.json()["raw_status"] == TripIngestion.PhaseStatus.QUEUED
    ingestion.refresh_from_db()
    assert ingestion.raw_status == TripIngestion.PhaseStatus.QUEUED
    job = HarJob.objects.get(trip=trip, kind=HarJob.Kind.FINAL_TRIP)
    assert len(callbacks) == 1
    assert delayed == [(job.id, ingestion.id)]


@pytest.mark.django_db
def test_process_trip_har_final_reads_raw_and_regenerates_segments(
    user,
    monkeypatch,
):
    start = timezone.now()
    trip = Trip.objects.create(
        user=user,
        client_session_id="har-final",
        device_id="test-device",
        status=Trip.Status.CLOSED,
        ended_at=start + timedelta(minutes=15),
    )
    StateTransition.objects.bulk_create(
        [
            StateTransition(
                trip=trip,
                from_state="STATIONARY",
                to_state="ACTIVE_TRACKING",
                reason="test-start",
                timestamp=start,
            ),
            StateTransition(
                trip=trip,
                from_state="ACTIVE_TRACKING",
                to_state="STATIONARY",
                reason="test-stop",
                timestamp=start + timedelta(minutes=10),
            ),
        ]
    )
    for offset, lon, lat, speed in [
        (1, 9.10, 45.46, 5.0),
        (4, 9.12, 45.47, 5.2),
        (8, 9.15, 45.49, 4.8),
        (11, 9.16, 45.50, 0.0),
        (14, 9.1605, 45.5005, 0.0),
    ]:
        GpsPoint.objects.create(
            trip=trip,
            timestamp=start + timedelta(minutes=offset),
            point=Point(lon, lat, srid=4326),
            speed_mps=speed,
        )

    ingestion = TripIngestion.objects.create(
        user=user,
        client_session_id="har-final",
        core_status=TripIngestion.PhaseStatus.COMPLETED,
        raw_status=TripIngestion.PhaseStatus.QUEUED,
        expected_raw_parts={PartKind.SENSOR_WINDOWS: 1},
        trip=trip,
    )
    TripIngestionPart.objects.create(
        ingestion=ingestion,
        kind=PartKind.SENSOR_WINDOWS,
        sequence=1,
        sha256="a" * 64,
        object_key="sensor_windows_part_0001.json.gz",
        received_at=timezone.now(),
    )
    job = HarJob.objects.create(trip=trip, kind=HarJob.Kind.FINAL_TRIP)
    raw = gzip.compress(json.dumps(_sensor_part_payload(start)).encode("utf-8"))
    monkeypatch.setattr(storage, "read_object", lambda object_key: raw)
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.MOVE,
        start_timestamp=start - timedelta(minutes=30),
        end_timestamp=start - timedelta(minutes=20),
        activity_label=ActivityLabel.WALKING,
    )

    result = process_trip_har_final.run(job.id, ingestion.id)

    ingestion.refresh_from_db()
    job.refresh_from_db()
    trip.refresh_from_db()
    assert ingestion.raw_status == TripIngestion.PhaseStatus.COMPLETED
    assert job.status == HarJob.Status.SUCCESS
    assert trip.status == Trip.Status.PROCESSED
    assert result["segments"] == 2
    assert MobilitySegment.objects.filter(trip=trip).count() == 2

    move = MobilitySegment.objects.get(trip=trip, kind=MobilitySegment.Kind.MOVE)
    stop = MobilitySegment.objects.get(trip=trip, kind=MobilitySegment.Kind.STOP)
    assert move.activity_label == ActivityLabel.BIKING
    assert move.path is not None
    assert len(move.path.coords) == 3
    assert move.distance_meters > 0
    assert stop.activity_label == ActivityLabel.IDLE
    assert stop.path is None
    assert stop.place is not None
    assert stop.place.dwell_seconds == 300


@pytest.mark.django_db
def test_process_trip_har_final_marks_storage_failure_retryable_without_cleanup(
    user,
    monkeypatch,
):
    start = timezone.now()
    trip, ingestion, job = _create_har_ingestion(
        user,
        session_id="har-storage-failure",
        start=start,
    )
    deleted: list[str] = []

    def fail_read(_object_key):
        raise RuntimeError("storage temporaneamente non disponibile")

    monkeypatch.setattr(storage, "read_object", fail_read)
    monkeypatch.setattr(storage, "delete_objects", lambda keys: deleted.extend(keys))

    with pytest.raises(RuntimeError, match="storage temporaneamente"):
        process_trip_har_final.run(job.id, ingestion.id)

    ingestion.refresh_from_db()
    job.refresh_from_db()
    trip.refresh_from_db()
    assert ingestion.raw_status == TripIngestion.PhaseStatus.FAILED_RETRYABLE
    assert "storage temporaneamente" in ingestion.error_message
    assert job.status == HarJob.Status.FAILURE
    assert "storage temporaneamente" in job.error
    assert trip.status == Trip.Status.CLOSED
    assert deleted == []


@pytest.mark.django_db
def test_process_trip_har_final_marks_invalid_payload_final_without_cleanup(
    user,
    monkeypatch,
):
    start = timezone.now()
    _trip, ingestion, job = _create_har_ingestion(
        user,
        session_id="har-invalid-final",
        start=start,
    )
    invalid_payload = {
        "windows": [
            {
                "window_start": start.isoformat(),
                "window_end": (start + timedelta(minutes=5)).isoformat(),
                "sample_rate_hz": 100,
                "sample_count": 499,
                "samples": [[0.0] * 9 for _ in range(499)],
            }
        ]
    }
    raw = gzip.compress(json.dumps(invalid_payload).encode("utf-8"))
    deleted: list[str] = []

    monkeypatch.setattr(process_trip_har_final, "max_retries", 0)
    monkeypatch.setattr(storage, "read_object", lambda object_key: raw)
    monkeypatch.setattr(storage, "delete_objects", lambda keys: deleted.extend(keys))

    with pytest.raises(ValueError, match="sample_count diverso da 500"):
        process_trip_har_final.run(job.id, ingestion.id)

    ingestion.refresh_from_db()
    job.refresh_from_db()
    assert ingestion.raw_status == TripIngestion.PhaseStatus.FAILED_FINAL
    assert "sample_count diverso da 500" in ingestion.error_message
    assert job.status == HarJob.Status.FAILURE
    assert "sample_count diverso da 500" in job.error
    assert deleted == []
