from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta

from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from ..models import HarJob, Trip, TripIngestion
from ..replay_raw import regenerate_raw_and_queue_har
from .materialization import (
    CoreMaterializationConflict,
    materialize_inline_core_ingestion,
    materialize_part_based_core_ingestion,
)
from .selectors import (
    locked_active_ingestions_for_owner,
    locked_owned_ingestions_for_owner,
)

ACTIVE_INGESTION_STALE_AFTER = timedelta(hours=24)
CORE_CLAIMABLE_STATUSES = {
    TripIngestion.PhaseStatus.PENDING,
    TripIngestion.PhaseStatus.RECEIVED,
    TripIngestion.PhaseStatus.QUEUED,
    TripIngestion.PhaseStatus.FAILED_RETRYABLE,
}


class IngestionServiceError(ValueError):
    status_code = 409

    def __init__(self, message: str):
        super().__init__(message)
        self.message = message


class IngestionNotFound(IngestionServiceError):
    status_code = 404


class IngestionForbidden(IngestionServiceError):
    status_code = 403


class IngestionGone(IngestionServiceError):
    status_code = 410


class IngestionBadRequest(IngestionServiceError):
    status_code = 400


@dataclass(frozen=True)
class StartRecordingResult:
    ingestion: TripIngestion
    already_exists: bool = False
    conflict_ingestion: TripIngestion | None = None


def start_recording(
    *,
    user_id: int,
    client_session_id: str,
    device_id: str,
    schema_version: int,
    timezone_name: str,
    app_version: str,
    device_platform: str,
    started_at: datetime | None = None,
    source_trip_id: int | None = None,
    now: datetime | None = None,
) -> StartRecordingResult:
    now = now or timezone.now()
    recording_started_at = started_at or now
    source_trip_id = _validate_source_trip(user_id, source_trip_id)

    with transaction.atomic():
        active = locked_active_ingestions_for_owner(user_id).first()
        if active is not None:
            if not _abandon_if_stale(active, now=now):
                if (
                    active.client_session_id == client_session_id
                    and active.device_id == device_id
                ):
                    return StartRecordingResult(active, already_exists=True)
                return StartRecordingResult(active, conflict_ingestion=active)

        ingestion = TripIngestion.objects.create(
            user_id=user_id,
            client_session_id=client_session_id,
            device_id=device_id,
            schema_version=schema_version,
            timezone=timezone_name,
            app_version=app_version,
            device_platform=device_platform,
            started_at=recording_started_at,
            recording_started_at=recording_started_at,
            last_seen_at=now,
            source_trip_id=source_trip_id,
        )
        if not ingestion.raw_base_path:
            ingestion.raw_base_path = f"ingestions/{ingestion.id}/"
            ingestion.save(update_fields=["raw_base_path", "updated_at"])
        return StartRecordingResult(ingestion)


def heartbeat_recording(
    *,
    user_id: int,
    ingestion_id: int,
    client_session_id: str,
    device_id: str,
    now: datetime | None = None,
) -> TripIngestion:
    now = now or timezone.now()
    with transaction.atomic():
        ingestion = _locked_owned_ingestion(user_id, ingestion_id)
        if ingestion.client_session_id != client_session_id:
            raise IngestionServiceError("client_session_id non corrisponde")
        if ingestion.device_id != device_id:
            raise IngestionForbidden("device_id non autorizzato")
        if (
            ingestion.recording_started_at is None
            or ingestion.recording_closed_at is not None
            or ingestion.recording_abandoned_at is not None
        ):
            raise IngestionServiceError("viaggio non attivo")
        ingestion.last_seen_at = now
        ingestion.save(update_fields=["last_seen_at", "updated_at"])
        return ingestion


def abandon_recording(
    *,
    user_id: int,
    ingestion_id: int,
    device_id: str,
    now: datetime | None = None,
) -> TripIngestion:
    now = now or timezone.now()
    with transaction.atomic():
        ingestion = _locked_owned_ingestion(user_id, ingestion_id)
        if ingestion.device_id != device_id:
            raise IngestionForbidden("solo il dispositivo origine puo' abbandonare")
        if ingestion.recording_closed_at is not None:
            raise IngestionServiceError("viaggio gia' chiuso")
        if ingestion.recording_abandoned_at is None:
            ingestion.recording_abandoned_at = now
            ingestion.save(update_fields=["recording_abandoned_at", "updated_at"])
        return ingestion


def release_active_lock_for_failed_final(
    ingestion: TripIngestion,
    *,
    now: datetime,
) -> None:
    if (
        ingestion.recording_started_at is not None
        and ingestion.recording_closed_at is None
        and ingestion.recording_abandoned_at is None
    ):
        ingestion.recording_closed_at = now
        ingestion.save(update_fields=["recording_closed_at", "updated_at"])


def process_inline_core_ingestion(
    *,
    user_id: int,
    payload,
    expected_raw_parts: dict[str, int],
    raw_status: str,
    actual_sha256: str,
    body_size: int,
) -> TripIngestion:
    with transaction.atomic():
        ingestion = _get_inline_core_ingestion(
            user_id=user_id,
            payload=payload,
            expected_raw_parts=expected_raw_parts,
            raw_status=raw_status,
            actual_sha256=actual_sha256,
            body_size=body_size,
        )
        if (
            ingestion.core_payload_sha256
            and ingestion.core_payload_sha256 != actual_sha256
        ):
            raise IngestionServiceError("client_session_id gia' usato con core diverso")
        if not ingestion.raw_base_path:
            ingestion.raw_base_path = f"ingestions/{ingestion.id}/"
            ingestion.save(update_fields=["raw_base_path", "updated_at"])

        if ingestion.core_status == TripIngestion.PhaseStatus.FAILED_FINAL:
            release_active_lock_for_failed_final(ingestion, now=timezone.now())
            raise IngestionServiceError("core ingestion fallita definitivamente")
        if ingestion.core_status in {
            TripIngestion.PhaseStatus.COMPLETED,
            TripIngestion.PhaseStatus.QUEUED,
            TripIngestion.PhaseStatus.PROCESSING,
        }:
            return ingestion
        if ingestion.core_status not in {
            TripIngestion.PhaseStatus.PENDING,
            TripIngestion.PhaseStatus.RECEIVING,
            TripIngestion.PhaseStatus.RECEIVED,
            TripIngestion.PhaseStatus.FAILED_RETRYABLE,
        }:
            raise IngestionServiceError(
                f"stato core non gestibile: {ingestion.core_status}"
            )

        now = timezone.now()
        ingestion.core_ingestion_mode = TripIngestion.CoreIngestionMode.INLINE
        ingestion.core_payload_sha256 = actual_sha256
        ingestion.core_payload_size_bytes = body_size
        ingestion.expected_core_parts = {}
        ingestion.expected_raw_parts = expected_raw_parts
        ingestion.raw_status = raw_status
        ingestion.device_id = payload.device_id
        ingestion.schema_version = payload.schema_version
        ingestion.started_at = payload.started_at
        ingestion.ended_at = payload.ended_at
        ingestion.timezone = payload.timezone
        ingestion.app_version = payload.app_version
        ingestion.device_platform = payload.device_platform
        ingestion.core_status = TripIngestion.PhaseStatus.PROCESSING
        ingestion.started_processing_at = now
        ingestion.error_message = ""
        ingestion.save(
            update_fields=[
                "core_ingestion_mode",
                "core_payload_sha256",
                "core_payload_size_bytes",
                "expected_core_parts",
                "expected_raw_parts",
                "raw_status",
                "device_id",
                "schema_version",
                "started_at",
                "ended_at",
                "timezone",
                "app_version",
                "device_platform",
                "core_status",
                "started_processing_at",
                "error_message",
                "updated_at",
            ]
        )

        if ingestion.source_trip_id is not None:
            _validate_replay_slot(
                user_id=user_id,
                client_session_id=ingestion.client_session_id,
                started_at=payload.started_at,
                ended_at=payload.ended_at,
            )

        try:
            materialized = materialize_inline_core_ingestion(ingestion, payload)
        except CoreMaterializationConflict as exc:
            raise IngestionServiceError(str(exc)) from exc
        trip = materialized.trip
        trip.refresh_from_db(fields=["distance_meters", "path"])

        ingestion.trip = trip
        ingestion.core_status = TripIngestion.PhaseStatus.COMPLETED
        ingestion.completed_at = now
        ingestion.failed_at = None
        if payload.ingestion_id is not None:
            ingestion.recording_closed_at = payload.ended_at or now
            ingestion.last_seen_at = now
        update_fields = [
            "trip",
            "core_status",
            "completed_at",
            "failed_at",
            "updated_at",
        ]
        if payload.ingestion_id is not None:
            update_fields.extend(["recording_closed_at", "last_seen_at"])
        ingestion.save(update_fields=update_fields)

        if ingestion.source_trip_id is not None:
            if payload.cutoff_source_timestamp is None:
                raise IngestionBadRequest(
                    "cutoff_source_timestamp richiesto per il replay"
                )
            ended_at = ingestion.recording_closed_at or now
            regenerate_raw_and_queue_har(
                ingestion,
                ingestion.source_trip,
                shift=ended_at - payload.cutoff_source_timestamp,
                now=now,
                cutoff=payload.cutoff_source_timestamp,
            )
        elif not expected_raw_parts:
            queue_final_har(ingestion, now=now)

        return ingestion


def queue_final_har(ingestion: TripIngestion, *, now: datetime) -> None:
    if ingestion.trip_id is None:
        raise IngestionServiceError("trip non materializzato per HAR finale")

    ingestion.raw_status = TripIngestion.PhaseStatus.QUEUED
    ingestion.queued_at = now
    ingestion.error_message = ""
    ingestion.save(
        update_fields=[
            "raw_status",
            "queued_at",
            "error_message",
            "updated_at",
        ]
    )
    job = HarJob.objects.create(
        trip_id=ingestion.trip_id,
        kind=HarJob.Kind.FINAL_TRIP,
    )
    from ..tasks import process_trip_har_final

    transaction.on_commit(lambda: process_trip_har_final.delay(job.id, ingestion.id))


def process_part_based_core_ingestion(
    ingestion_id: int,
    *,
    will_retry_on_error: bool,
) -> dict:
    with transaction.atomic():
        ingestion = TripIngestion.objects.select_for_update().get(id=ingestion_id)
        if ingestion.core_status == TripIngestion.PhaseStatus.COMPLETED:
            return {"skipped": "core ingestion already completed"}
        if ingestion.core_status not in CORE_CLAIMABLE_STATUSES:
            return {"skipped": f"core ingestion is {ingestion.core_status}"}

        ingestion.core_status = TripIngestion.PhaseStatus.PROCESSING
        ingestion.started_processing_at = timezone.now()
        ingestion.save(
            update_fields=["core_status", "started_processing_at", "updated_at"]
        )

    try:
        with transaction.atomic():
            materialized = materialize_part_based_core_ingestion(ingestion)
            trip = materialized.trip

            ingestion.trip = trip
            ingestion.core_status = TripIngestion.PhaseStatus.COMPLETED
            ingestion.error_message = ""
            ingestion.completed_at = timezone.now()
            ingestion.save(
                update_fields=[
                    "trip",
                    "core_status",
                    "error_message",
                    "completed_at",
                    "updated_at",
                ]
            )
    except Exception as exc:
        _mark_part_based_core_ingestion_failed(
            ingestion,
            exc,
            will_retry=will_retry_on_error,
        )
        raise

    return {
        "trip_id": trip.id,
        "gps_points": materialized.gps_points,
        "path_points": materialized.path_points,
        "state_transitions": materialized.state_transitions,
    }


def ensure_ingestion_not_permanently_dead(ingestion: TripIngestion) -> None:
    if ingestion.recording_abandoned_at is not None:
        raise IngestionGone("viaggio abbandonato")
    if (
        ingestion.recording_closed_at is not None
        and ingestion.core_status != TripIngestion.PhaseStatus.COMPLETED
    ):
        raise IngestionGone("viaggio gia' chiuso")


def _locked_owned_ingestion(user_id: int, ingestion_id: int) -> TripIngestion:
    ingestion = (
        locked_owned_ingestions_for_owner(user_id)
        .filter(id=ingestion_id)
        .first()
    )
    if ingestion is None:
        raise IngestionNotFound("ingestion non trovata")
    return ingestion


def _get_inline_core_ingestion(
    *,
    user_id: int,
    payload,
    expected_raw_parts: dict[str, int],
    raw_status: str,
    actual_sha256: str,
    body_size: int,
) -> TripIngestion:
    if payload.ingestion_id is None:
        ingestion, _ = TripIngestion.objects.select_for_update().get_or_create(
            user_id=user_id,
            client_session_id=payload.client_session_id,
            defaults={
                "device_id": payload.device_id,
                "schema_version": payload.schema_version,
                "expected_core_parts": {},
                "expected_raw_parts": expected_raw_parts,
                "raw_status": raw_status,
                "core_ingestion_mode": TripIngestion.CoreIngestionMode.INLINE,
                "core_payload_sha256": actual_sha256,
                "core_payload_size_bytes": body_size,
                "started_at": payload.started_at,
                "ended_at": payload.ended_at,
                "timezone": payload.timezone,
                "app_version": payload.app_version,
                "device_platform": payload.device_platform,
            },
        )
        return ingestion

    ingestion = _locked_owned_ingestion(user_id, payload.ingestion_id)
    if ingestion.client_session_id != payload.client_session_id:
        raise IngestionServiceError("client_session_id non corrisponde")
    if ingestion.device_id != payload.device_id:
        raise IngestionForbidden("device_id non autorizzato")
    if ingestion.recording_started_at is None:
        raise IngestionServiceError("viaggio non avviato")
    ensure_ingestion_not_permanently_dead(ingestion)
    return ingestion


def _active_last_seen(ingestion: TripIngestion) -> datetime:
    return (
        ingestion.last_seen_at
        or ingestion.recording_started_at
        or ingestion.created_at
    )


def _abandon_if_stale(
    ingestion: TripIngestion,
    *,
    now: datetime,
) -> bool:
    if now - _active_last_seen(ingestion) < ACTIVE_INGESTION_STALE_AFTER:
        return False
    ingestion.recording_abandoned_at = now
    ingestion.save(update_fields=["recording_abandoned_at", "updated_at"])
    return True


def _validate_source_trip(user_id: int, source_trip_id: int | None) -> int | None:
    if source_trip_id is None:
        return None
    if not Trip.objects.filter(
        id=source_trip_id,
        user_id=user_id,
        is_reloadable=True,
        status__in=[Trip.Status.CLOSED, Trip.Status.PROCESSED],
    ).exists():
        raise IngestionServiceError("viaggio sorgente non ricaricabile")
    return source_trip_id


def _validate_replay_slot(
    *,
    user_id: int,
    client_session_id: str,
    started_at: datetime | None,
    ended_at: datetime | None,
) -> None:
    if started_at is None or ended_at is None:
        return
    if ended_at > timezone.now():
        raise IngestionServiceError("scegli uno slot nel passato")
    overlaps = (
        Trip.objects.filter(user_id=user_id, started_at__lt=ended_at)
        .filter(Q(ended_at__isnull=True) | Q(ended_at__gt=started_at))
        .exclude(client_session_id=client_session_id)
        .exists()
    )
    if overlaps:
        raise IngestionServiceError("slot sovrapposto a un viaggio esistente")


def _mark_part_based_core_ingestion_failed(
    ingestion: TripIngestion,
    exc: Exception,
    *,
    will_retry: bool,
) -> None:
    failed_at = timezone.now()
    ingestion.core_status = (
        TripIngestion.PhaseStatus.FAILED_RETRYABLE
        if will_retry
        else TripIngestion.PhaseStatus.FAILED_FINAL
    )
    ingestion.error_message = str(exc)
    ingestion.failed_at = failed_at
    update_fields = ["core_status", "error_message", "failed_at", "updated_at"]
    if (
        not will_retry
        and ingestion.recording_started_at is not None
        and ingestion.recording_closed_at is None
        and ingestion.recording_abandoned_at is None
    ):
        ingestion.recording_closed_at = failed_at
        update_fields.append("recording_closed_at")
    ingestion.save(update_fields=update_fields)
