import json
import gzip
import struct
from datetime import timedelta

import pytest
from django.contrib.auth import get_user_model
from django.test import Client
from django.utils import timezone

from accounts.models import AccessToken
from mobility.ingestion.api import _inline_payload_sha256
from mobility.ingestion.schemas import InlineCoreIn
from mobility.models import HarJob, PartKind, Trip, TripIngestion, TripIngestionPart
from mobility.tasks import process_trip_har_final


@pytest.fixture
def mobile_user(db):
    return get_user_model().objects.create_user(
        username="mobile@example.com",
        email="mobile@example.com",
        password="password-123",
    )


@pytest.fixture
def auth_headers(mobile_user) -> dict:
    raw_token, _access_token = AccessToken.issue_for_user(mobile_user)
    return {"HTTP_AUTHORIZATION": f"Bearer {raw_token}"}


def _iso(value):
    return value.isoformat().replace("+00:00", "Z")


def _core_body_without_raw(*, session_id: str, started_at, ended_at) -> dict:
    return _core_body(
        session_id=session_id,
        started_at=started_at,
        ended_at=ended_at,
        expected_raw_parts={},
    )


def _core_body(*, session_id: str, started_at, ended_at, expected_raw_parts) -> dict:
    body = {
        "client_session_id": session_id,
        "schema_version": 1,
        "started_at": _iso(started_at),
        "ended_at": _iso(ended_at),
        "timezone": "",
        "device_id": "device-1",
        "app_version": "",
        "device_platform": "",
        "gps_points": [
            {
                "timestamp": _iso(started_at),
                "latitude": 45.4642,
                "longitude": 9.19,
                "speed_mps": 1.2,
                "accuracy_meters": 5,
            },
            {
                "timestamp": _iso(started_at + timedelta(minutes=5)),
                "latitude": 45.465,
                "longitude": 9.2,
                "speed_mps": 1.4,
                "accuracy_meters": 5,
            },
        ],
        "state_transitions": [
            {
                "timestamp": _iso(started_at + timedelta(minutes=1)),
                "from_state": "STATIONARY",
                "to_state": "MOVEMENT",
                "reason": "gps_reliable_motion_confirmed_in_stationary",
                "sigma": 0.2,
                "speed_mps": 1.2,
            }
        ],
        "expected_raw_parts": expected_raw_parts,
        "core_payload_sha256": "",
    }
    body["core_payload_sha256"] = _inline_payload_sha256(InlineCoreIn(**body))
    return body


def _binary_sensor_windows_gz(started_at) -> bytes:
    header = struct.pack("<8sI", b"MDHARW1\x00", 1)
    window_header = struct.pack(
        "<qqIII",
        int(started_at.timestamp() * 1_000_000),
        int((started_at + timedelta(seconds=5)).timestamp() * 1_000_000),
        100,
        500,
        6,
    )
    matrix = b"".join(struct.pack("<f", 0.1) for _ in range(500 * 6))
    return gzip.compress(header + window_header + matrix)


@pytest.mark.django_db
def test_inline_core_without_raw_queues_gps_only_enrichment(
    mobile_user,
    auth_headers,
):
    started_at = timezone.now() - timedelta(minutes=10)
    ended_at = timezone.now()
    body = _core_body_without_raw(
        session_id="real-no-raw",
        started_at=started_at,
        ended_at=ended_at,
    )

    response = Client().post(
        "/api/ingestion/trips/core",
        data=json.dumps(body),
        content_type="application/json",
        **auth_headers,
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["core_status"] == TripIngestion.PhaseStatus.COMPLETED
    assert payload["raw_status"] == TripIngestion.PhaseStatus.QUEUED

    ingestion = TripIngestion.objects.get(client_session_id="real-no-raw")
    assert ingestion.expected_raw_parts == {}
    assert ingestion.raw_status == TripIngestion.PhaseStatus.QUEUED
    assert ingestion.trip.status == Trip.Status.CLOSED
    job = HarJob.objects.get(
        trip=ingestion.trip,
        kind=HarJob.Kind.FINAL_TRIP,
    )

    process_trip_har_final.apply(args=(job.id, ingestion.id), throw=True)

    ingestion.refresh_from_db()
    ingestion.trip.refresh_from_db()
    job.refresh_from_db()
    assert ingestion.raw_status == TripIngestion.PhaseStatus.COMPLETED
    assert ingestion.trip.status == Trip.Status.PROCESSED
    assert job.status == HarJob.Status.SUCCESS


@pytest.mark.django_db
def test_complete_raw_with_binary_sensor_windows_processes_real_trip(
    mobile_user,
    auth_headers,
    monkeypatch,
):
    started_at = timezone.now() - timedelta(minutes=10)
    ended_at = timezone.now()
    body = _core_body(
        session_id="real-with-raw",
        started_at=started_at,
        ended_at=ended_at,
        expected_raw_parts={PartKind.SENSOR_WINDOWS: 1},
    )

    core_response = Client().post(
        "/api/ingestion/trips/core",
        data=json.dumps(body),
        content_type="application/json",
        **auth_headers,
    )

    assert core_response.status_code == 200
    ingestion = TripIngestion.objects.get(client_session_id="real-with-raw")
    assert ingestion.raw_status == TripIngestion.PhaseStatus.PENDING

    object_key = f"{ingestion.raw_base_path}sensor_windows_part_0001.bin.gz"
    raw_body = _binary_sensor_windows_gz(started_at + timedelta(minutes=2))
    TripIngestionPart.objects.create(
        ingestion=ingestion,
        kind=PartKind.SENSOR_WINDOWS,
        sequence=1,
        sha256="test-sha",
        size_bytes=len(raw_body),
        object_key=object_key,
        received_at=timezone.now(),
    )
    monkeypatch.setattr(
        "mobility.ingestion.storage.read_object",
        lambda key: raw_body if key == object_key else b"",
    )

    complete_response = Client().post(
        f"/api/ingestion/trips/{ingestion.id}/complete-raw",
        data=json.dumps({"total_parts": 1}),
        content_type="application/json",
        **auth_headers,
    )

    assert complete_response.status_code == 202
    ingestion.refresh_from_db()
    assert ingestion.raw_status == TripIngestion.PhaseStatus.QUEUED
    job = HarJob.objects.get(trip=ingestion.trip, kind=HarJob.Kind.FINAL_TRIP)

    process_trip_har_final.apply(args=(job.id, ingestion.id), throw=True)

    ingestion.refresh_from_db()
    ingestion.trip.refresh_from_db()
    job.refresh_from_db()
    assert ingestion.raw_status == TripIngestion.PhaseStatus.COMPLETED
    assert ingestion.trip.status == Trip.Status.PROCESSED
    assert job.status == HarJob.Status.SUCCESS
