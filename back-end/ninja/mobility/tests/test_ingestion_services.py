from datetime import timedelta

import pytest
from django.contrib.auth import get_user_model
from django.utils import timezone

from mobility.ingestion.services import (
    IngestionForbidden,
    IngestionServiceError,
    abandon_recording,
    heartbeat_recording,
    process_part_based_core_ingestion,
    start_recording,
)
from mobility.models import TripIngestion


@pytest.fixture
def mobile_user(db):
    return get_user_model().objects.create_user(
        username="service-mobile@example.com",
        email="service-mobile@example.com",
        password="password-123",
    )


def _start_recording(user_id: int, **overrides):
    payload = {
        "user_id": user_id,
        "client_session_id": "session-1",
        "device_id": "device-1",
        "schema_version": 1,
        "timezone_name": "Europe/Rome",
        "app_version": "1.0.0",
        "device_platform": "ios",
    }
    payload.update(overrides)
    return start_recording(**payload)


@pytest.mark.django_db
def test_start_recording_creates_active_ingestion(mobile_user):
    started_at = timezone.now() - timedelta(minutes=5)

    result = _start_recording(mobile_user.id, started_at=started_at)

    assert result.already_exists is False
    assert result.conflict_ingestion is None
    assert result.ingestion.user_id == mobile_user.id
    assert result.ingestion.recording_started_at == started_at
    assert result.ingestion.last_seen_at is not None
    assert result.ingestion.raw_base_path == f"ingestions/{result.ingestion.id}/"


@pytest.mark.django_db
def test_start_recording_returns_existing_for_same_session_and_device(mobile_user):
    first = _start_recording(mobile_user.id)

    second = _start_recording(mobile_user.id)

    assert second.already_exists is True
    assert second.ingestion.id == first.ingestion.id
    assert TripIngestion.objects.filter(user=mobile_user).count() == 1


@pytest.mark.django_db
def test_start_recording_returns_conflict_for_different_active_device(mobile_user):
    first = _start_recording(mobile_user.id)

    conflict = _start_recording(
        mobile_user.id,
        client_session_id="session-2",
        device_id="device-2",
    )

    assert conflict.conflict_ingestion == first.ingestion
    assert TripIngestion.objects.filter(user=mobile_user).count() == 1


@pytest.mark.django_db
def test_start_recording_abandons_stale_active_ingestion(mobile_user):
    now = timezone.now()
    stale = _start_recording(
        mobile_user.id,
        now=now - timedelta(hours=25),
    ).ingestion

    result = _start_recording(
        mobile_user.id,
        client_session_id="session-2",
        device_id="device-2",
        now=now,
    )

    stale.refresh_from_db()
    assert stale.recording_abandoned_at == now
    assert result.ingestion.id != stale.id
    assert result.ingestion.recording_abandoned_at is None


@pytest.mark.django_db
def test_heartbeat_recording_updates_last_seen(mobile_user):
    ingestion = _start_recording(mobile_user.id).ingestion
    now = timezone.now()

    updated = heartbeat_recording(
        user_id=mobile_user.id,
        ingestion_id=ingestion.id,
        client_session_id=ingestion.client_session_id,
        device_id=ingestion.device_id,
        now=now,
    )

    assert updated.last_seen_at == now


@pytest.mark.django_db
def test_heartbeat_recording_rejects_wrong_device(mobile_user):
    ingestion = _start_recording(mobile_user.id).ingestion

    with pytest.raises(IngestionForbidden, match="device_id non autorizzato"):
        heartbeat_recording(
            user_id=mobile_user.id,
            ingestion_id=ingestion.id,
            client_session_id=ingestion.client_session_id,
            device_id="other-device",
        )


@pytest.mark.django_db
def test_abandon_recording_sets_abandoned_at(mobile_user):
    ingestion = _start_recording(mobile_user.id).ingestion
    now = timezone.now()

    abandoned = abandon_recording(
        user_id=mobile_user.id,
        ingestion_id=ingestion.id,
        device_id=ingestion.device_id,
        now=now,
    )

    assert abandoned.recording_abandoned_at == now


@pytest.mark.django_db
def test_abandon_recording_rejects_closed_ingestion(mobile_user):
    ingestion = _start_recording(mobile_user.id).ingestion
    ingestion.recording_closed_at = timezone.now()
    ingestion.save(update_fields=["recording_closed_at", "updated_at"])

    with pytest.raises(IngestionServiceError, match="viaggio gia' chiuso"):
        abandon_recording(
            user_id=mobile_user.id,
            ingestion_id=ingestion.id,
            device_id=ingestion.device_id,
        )


@pytest.mark.django_db
def test_process_part_based_core_ingestion_skips_already_completed(mobile_user):
    ingestion = TripIngestion.objects.create(
        user=mobile_user,
        client_session_id="completed-core",
        core_status=TripIngestion.PhaseStatus.COMPLETED,
    )

    assert process_part_based_core_ingestion(
        ingestion.id,
        will_retry_on_error=False,
    ) == {"skipped": "core ingestion already completed"}


@pytest.mark.django_db
def test_process_part_based_core_ingestion_skips_unclaimable_status(mobile_user):
    ingestion = TripIngestion.objects.create(
        user=mobile_user,
        client_session_id="processing-core",
        core_status=TripIngestion.PhaseStatus.PROCESSING,
    )

    assert process_part_based_core_ingestion(
        ingestion.id,
        will_retry_on_error=False,
    ) == {"skipped": f"core ingestion is {TripIngestion.PhaseStatus.PROCESSING}"}
