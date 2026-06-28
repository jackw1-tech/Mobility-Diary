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
    PlaceMiningStatus,
    StateTransition,
    Trip,
    TripIngestion,
    TripIngestionPart,
    VirtualStopInterval,
)
from mobility.ml.classifier import ClassifierResult
from mobility.tasks import InvalidRawSensorPayload, process_trip_har_final


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
def test_complete_raw_rejects_when_core_is_not_completed(user):
    ingestion = TripIngestion.objects.create(
        user=user,
        client_session_id="har-core-pending",
        core_status=TripIngestion.PhaseStatus.PROCESSING,
        raw_status=TripIngestion.PhaseStatus.RECEIVED,
        expected_raw_parts={PartKind.SENSOR_WINDOWS: 1},
    )

    response = Client().post(
        f"/api/ingestion/trips/{ingestion.id}/complete-raw",
        data=stable_json({"manifest_sha256": "b" * 64, "total_parts": 1}).decode(
            "utf-8"
        ),
        content_type="application/json",
        **auth_headers(user),
    )

    assert response.status_code == 409
    assert "core ingestion non ancora completata" in response.json()["detail"]


@pytest.mark.django_db
def test_complete_raw_rejects_when_raw_parts_are_missing(user):
    trip = Trip.objects.create(
        user=user,
        client_session_id="har-missing-raw",
        device_id="test-device",
        status=Trip.Status.CLOSED,
    )
    ingestion = TripIngestion.objects.create(
        user=user,
        client_session_id="har-missing-raw",
        core_status=TripIngestion.PhaseStatus.COMPLETED,
        raw_status=TripIngestion.PhaseStatus.RECEIVED,
        expected_raw_parts={PartKind.SENSOR_WINDOWS: 1},
        trip=trip,
    )

    response = Client().post(
        f"/api/ingestion/trips/{ingestion.id}/complete-raw",
        data=stable_json({"manifest_sha256": "b" * 64, "total_parts": 1}).decode(
            "utf-8"
        ),
        content_type="application/json",
        **auth_headers(user),
    )

    assert response.status_code == 409
    assert "parti raw mancanti" in response.json()["detail"]


@pytest.mark.django_db
@pytest.mark.parametrize(
    "raw_status",
    [
        TripIngestion.PhaseStatus.QUEUED,
        TripIngestion.PhaseStatus.PROCESSING,
        TripIngestion.PhaseStatus.COMPLETED,
        TripIngestion.PhaseStatus.FAILED_RETRYABLE,
    ],
)
def test_complete_raw_is_idempotent_for_terminal_or_backend_owned_states(
    user,
    raw_status,
):
    trip = Trip.objects.create(
        user=user,
        client_session_id=f"har-idempotent-{raw_status}",
        device_id="test-device",
        status=Trip.Status.CLOSED,
    )
    ingestion = TripIngestion.objects.create(
        user=user,
        client_session_id=f"har-idempotent-{raw_status}",
        core_status=TripIngestion.PhaseStatus.COMPLETED,
        raw_status=raw_status,
        expected_raw_parts={PartKind.SENSOR_WINDOWS: 1},
        trip=trip,
    )

    response = Client().post(
        f"/api/ingestion/trips/{ingestion.id}/complete-raw",
        data=stable_json({"manifest_sha256": "b" * 64, "total_parts": 1}).decode(
            "utf-8"
        ),
        content_type="application/json",
        **auth_headers(user),
    )

    ingestion.refresh_from_db()
    assert response.status_code == 202
    assert response.json()["raw_status"] == raw_status
    assert ingestion.raw_status == raw_status
    assert not HarJob.objects.filter(trip=trip).exists()


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
                to_state="MOVEMENT",
                reason="test-start",
                timestamp=start,
            ),
            StateTransition(
                trip=trip,
                from_state="MOVEMENT",
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
    deleted: list[str] = []
    monkeypatch.setattr(storage, "read_object", lambda object_key: raw)
    monkeypatch.setattr(storage, "delete_objects", lambda keys: deleted.extend(keys))
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
    # La scoperta dei luoghi e' user-scoped (ADR 0029): il diario non persiste
    # piu' riferimenti strutturali a luoghi trip-scoped sui segmenti.
    assert not any(field.name == "place" for field in stop._meta.get_fields())
    assert deleted == []


@pytest.mark.django_db
def test_process_trip_har_final_materializes_virtual_stop_intervals(
    user,
    monkeypatch,
):
    start = timezone.now()
    trip = Trip.objects.create(
        user=user,
        client_session_id="har-final-virtual-stop",
        device_id="test-device",
        status=Trip.Status.CLOSED,
        ended_at=start + timedelta(minutes=12),
    )
    StateTransition.objects.bulk_create(
        [
            StateTransition(
                trip=trip,
                from_state="STATIONARY",
                to_state="MOVEMENT",
                reason="test-start",
                timestamp=start,
            ),
            StateTransition(
                trip=trip,
                from_state="MOVEMENT",
                to_state="STATIONARY",
                reason="test-stop",
                timestamp=start + timedelta(minutes=10),
            ),
        ]
    )
    for offset, lon, lat, speed in [
        (1, 9.10, 45.46, 2.0),
        (4, 9.12, 45.47, 2.2),
        (8, 9.15, 45.49, 0.0),
        (9, 9.1502, 45.4902, 0.0),
    ]:
        GpsPoint.objects.create(
            trip=trip,
            timestamp=start + timedelta(minutes=offset),
            point=Point(lon, lat, srid=4326),
            speed_mps=speed,
        )

    ingestion = TripIngestion.objects.create(
        user=user,
        client_session_id="har-final-virtual-stop",
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
    monkeypatch.setattr(storage, "delete_objects", lambda _keys: None)
    monkeypatch.setattr(
        "mobility.ml.pipeline.classify_windows",
        lambda *_args, **_kwargs: ClassifierResult(
            labels=[ActivityLabel.WALKING, ActivityLabel.IDLE],
            summary={"classifier": "fake"},
        ),
    )
    monkeypatch.setattr(
        "mobility.ml.pipeline.correct_idle_with_gps",
        lambda labels, _speeds: labels,
    )

    result = process_trip_har_final.run(job.id, ingestion.id)

    segments = list(trip.segments.order_by("start_timestamp"))
    virtual_stop = VirtualStopInterval.objects.get(trip=trip)
    assert result["segments"] == 2
    assert result["virtual_stop_intervals"] == 1
    assert [segment.kind for segment in segments] == [
        MobilitySegment.Kind.MOVE,
        MobilitySegment.Kind.STOP,
    ]
    assert [segment.activity_label for segment in segments] == [
        ActivityLabel.WALKING,
        ActivityLabel.IDLE,
    ]
    assert virtual_stop.start_timestamp == start + timedelta(minutes=5)
    assert virtual_stop.end_timestamp == start + timedelta(minutes=10)


@pytest.mark.django_db
def test_process_trip_har_final_publishes_enriched_after_commit(
    user,
    monkeypatch,
    django_capture_on_commit_callbacks,
):
    start = timezone.now()
    trip, ingestion, job = _create_har_ingestion(
        user,
        session_id="har-publish-success",
        start=start,
    )
    raw = gzip.compress(json.dumps(_sensor_part_payload(start)).encode("utf-8"))
    published = []

    def fake_pipeline(trip, *, sensor_windows):
        trip.status = Trip.Status.PROCESSED
        trip.save(update_fields=["status", "updated_at"])
        return {"segments": 0}

    monkeypatch.setattr(storage, "read_object", lambda object_key: raw)
    monkeypatch.setattr("mobility.tasks.run_pipeline", fake_pipeline)
    monkeypatch.setattr(
        "mobility.diary_events.publish_diary_status",
        lambda *args, **kwargs: published.append((args, kwargs)),
    )

    monkeypatch.setattr(
        "mobility.tasks.mine_significant_places.delay", lambda user_id: None
    )

    with django_capture_on_commit_callbacks(execute=False) as callbacks:
        process_trip_har_final.run(job.id, ingestion.id)

    status = PlaceMiningStatus.objects.get(user=user)
    assert status.status == PlaceMiningStatus.Status.PENDING
    assert status.requested_at is not None
    assert status.started_at is None
    assert status.finished_at is None
    assert published == []
    # Due callback post-commit: pubblicazione diario (prima) + mining luoghi.
    assert len(callbacks) == 2
    callbacks[0]()
    assert published == [((trip.id, "enriched"), {"reason": None})]


@pytest.mark.django_db
def test_process_trip_har_final_schedules_place_mining_after_commit(
    user,
    monkeypatch,
    django_capture_on_commit_callbacks,
):
    start = timezone.now()
    trip, ingestion, job = _create_har_ingestion(
        user,
        session_id="har-mining",
        start=start,
    )
    raw = gzip.compress(json.dumps(_sensor_part_payload(start)).encode("utf-8"))
    mined = []

    def fake_pipeline(trip, *, sensor_windows):
        trip.status = Trip.Status.PROCESSED
        trip.save(update_fields=["status", "updated_at"])
        return {"segments": 0}

    monkeypatch.setattr(storage, "read_object", lambda object_key: raw)
    monkeypatch.setattr("mobility.tasks.run_pipeline", fake_pipeline)
    monkeypatch.setattr(
        "mobility.diary_events.publish_diary_status", lambda *a, **k: None
    )
    monkeypatch.setattr(
        "mobility.tasks.mine_significant_places.delay",
        lambda user_id: mined.append(user_id),
    )

    with django_capture_on_commit_callbacks(execute=True):
        process_trip_har_final.run(job.id, ingestion.id)

    status = PlaceMiningStatus.objects.get(user=user)
    assert status.status == PlaceMiningStatus.Status.PENDING
    # Il mining dei luoghi parte dopo l'arricchimento finale, per quell'utente.
    assert mined == [user.id]


@pytest.mark.django_db
def test_process_trip_har_final_coalesces_place_mining_if_user_already_running(
    user,
    monkeypatch,
    django_capture_on_commit_callbacks,
):
    start = timezone.now()
    trip, ingestion, job = _create_har_ingestion(
        user,
        session_id="har-mining-coalesced",
        start=start,
    )
    PlaceMiningStatus.objects.create(
        user=user,
        status=PlaceMiningStatus.Status.RUNNING,
        requested_at=start - timedelta(minutes=10),
        started_at=start - timedelta(minutes=9),
    )
    raw = gzip.compress(json.dumps(_sensor_part_payload(start)).encode("utf-8"))
    published = []

    def fake_pipeline(trip, *, sensor_windows):
        trip.status = Trip.Status.PROCESSED
        trip.save(update_fields=["status", "updated_at"])
        return {"segments": 0}

    monkeypatch.setattr(storage, "read_object", lambda object_key: raw)
    monkeypatch.setattr("mobility.tasks.run_pipeline", fake_pipeline)
    monkeypatch.setattr(
        "mobility.diary_events.publish_diary_status",
        lambda *args, **kwargs: published.append((args, kwargs)),
    )
    monkeypatch.setattr(
        "mobility.tasks.mine_significant_places.delay",
        lambda user_id: pytest.fail("non deve schedulare subito una seconda run"),
    )

    with django_capture_on_commit_callbacks(execute=False) as callbacks:
        process_trip_har_final.run(job.id, ingestion.id)

    status = PlaceMiningStatus.objects.get(user=user)
    assert status.status == PlaceMiningStatus.Status.RUNNING
    assert status.rerun_requested is True
    assert published == []
    assert len(callbacks) == 1
    callbacks[0]()
    assert published == [((trip.id, "enriched"), {"reason": None})]


@pytest.mark.django_db
def test_process_trip_har_final_publishes_final_failure_after_commit(
    user,
    monkeypatch,
    django_capture_on_commit_callbacks,
):
    start = timezone.now()
    trip, ingestion, job = _create_har_ingestion(
        user,
        session_id="har-publish-failure",
        start=start,
    )
    published = []

    monkeypatch.setattr(storage, "read_object", lambda object_key: b"not-gzip")
    monkeypatch.setattr(
        "mobility.diary_events.publish_diary_status",
        lambda *args, **kwargs: published.append((args, kwargs)),
    )

    with django_capture_on_commit_callbacks(execute=False) as callbacks:
        with pytest.raises(InvalidRawSensorPayload):
            process_trip_har_final.run(job.id, ingestion.id)

    assert published == []
    assert len(callbacks) == 1
    callbacks[0]()
    assert published == [
        ((trip.id, "failed"), {"reason": "diary_enrichment_failed"})
    ]


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
def test_process_trip_har_final_marks_model_failure_final_after_retry_exhausted(
    user,
    monkeypatch,
):
    start = timezone.now()
    _trip, ingestion, job = _create_har_ingestion(
        user,
        session_id="har-model-final",
        start=start,
    )
    raw = gzip.compress(json.dumps(_sensor_part_payload(start)).encode("utf-8"))

    def fail_pipeline(_trip, *, sensor_windows):
        raise RuntimeError("modello HAR non caricabile")

    monkeypatch.setattr(process_trip_har_final, "max_retries", 0)
    monkeypatch.setattr(storage, "read_object", lambda object_key: raw)
    monkeypatch.setattr("mobility.tasks.run_pipeline", fail_pipeline)

    with pytest.raises(RuntimeError, match="modello HAR"):
        process_trip_har_final.run(job.id, ingestion.id)

    ingestion.refresh_from_db()
    job.refresh_from_db()
    assert ingestion.raw_status == TripIngestion.PhaseStatus.FAILED_FINAL
    assert "modello HAR" in ingestion.error_message
    assert job.status == HarJob.Status.FAILURE


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

    with pytest.raises(InvalidRawSensorPayload, match="sample_count diverso da 500"):
        process_trip_har_final.run(job.id, ingestion.id)

    ingestion.refresh_from_db()
    job.refresh_from_db()
    assert ingestion.raw_status == TripIngestion.PhaseStatus.FAILED_FINAL
    assert "sample_count diverso da 500" in ingestion.error_message
    assert job.status == HarJob.Status.FAILURE
    assert "sample_count diverso da 500" in job.error
    assert deleted == []


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("raw", "match"),
    [
        (b"not-gzip", "gzip non valido"),
        (gzip.compress(b"{"), "JSON non valido"),
    ],
)
def test_process_trip_har_final_marks_unreadable_payload_final(
    user,
    monkeypatch,
    raw,
    match,
):
    start = timezone.now()
    _trip, ingestion, job = _create_har_ingestion(
        user,
        session_id=f"har-unreadable-{match}",
        start=start,
    )

    monkeypatch.setattr(storage, "read_object", lambda object_key: raw)

    with pytest.raises(InvalidRawSensorPayload, match=match):
        process_trip_har_final.run(job.id, ingestion.id)

    ingestion.refresh_from_db()
    job.refresh_from_db()
    assert ingestion.raw_status == TripIngestion.PhaseStatus.FAILED_FINAL
    assert match in ingestion.error_message
    assert job.status == HarJob.Status.FAILURE


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("window_patch", "match"),
    [
        ({"window_start": None}, "timestamp raw non valido"),
        ({"sample_rate_hz": 0}, "sample_rate_hz non valido"),
        (
            {"samples": [[0.0] * 5 for _ in range(500)]},
            "riga matrice non valida",
        ),
    ],
)
def test_process_trip_har_final_marks_structurally_invalid_window_final(
    user,
    monkeypatch,
    window_patch,
    match,
):
    start = timezone.now()
    _trip, ingestion, job = _create_har_ingestion(
        user,
        session_id=f"har-invalid-{match}",
        start=start,
    )
    payload = _sensor_part_payload(start)
    payload["windows"][0].update(window_patch)
    raw = gzip.compress(json.dumps(payload).encode("utf-8"))

    monkeypatch.setattr(storage, "read_object", lambda object_key: raw)

    with pytest.raises(InvalidRawSensorPayload, match=match):
        process_trip_har_final.run(job.id, ingestion.id)

    ingestion.refresh_from_db()
    job.refresh_from_db()
    assert ingestion.raw_status == TripIngestion.PhaseStatus.FAILED_FINAL
    assert match in ingestion.error_message
    assert job.status == HarJob.Status.FAILURE
