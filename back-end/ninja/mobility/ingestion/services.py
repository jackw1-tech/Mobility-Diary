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
)
from .selectors import locked_active_ingestions_for_owner

ACTIVE_INGESTION_STALE_AFTER = timedelta(hours=24)


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


class IngestionUnprocessable(IngestionServiceError):
    status_code = 422


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
            started_at=recording_started_at,
            recording_started_at=recording_started_at,
            last_seen_at=now,
            source_trip_id=source_trip_id,
        )
        if not ingestion.raw_base_path:
            ingestion.raw_base_path = f"ingestions/{ingestion.id}/"
            ingestion.save(update_fields=["raw_base_path", "updated_at"])
        return StartRecordingResult(ingestion)


"""
Funzione che aggiorna il last_seen_at della trip ingestion interrogata anche se non è più vecchia d 24 ore
"""
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
        ingestion.last_seen_at = now
        ingestion.save(update_fields=["last_seen_at", "updated_at"])
        
        return ingestion

"""
Funzione che chiude la trip ingestion interrogata, segnando il recording_closed_at
"""
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



""" 
Funzione che esegue tutta la fase di caricamento core del viaggio 
"""
def process_inline_core_ingestion(
    user_id: int,
    payload,
    expected_raw_parts: int,
    raw_status: str,
    body_size: int,
) -> TripIngestion:
    with transaction.atomic():
        ingestion = _get_inline_core_ingestion(
            user_id=user_id,
            payload=payload,
            expected_raw_parts=expected_raw_parts,
            raw_status=raw_status,
            body_size=body_size,
        )
        
        if not ingestion.raw_base_path:
            ingestion.raw_base_path = f"ingestions/{ingestion.id}/"
            ingestion.save(update_fields=["raw_base_path", "updated_at"])

        now = timezone.now()
        ingestion.core_payload_size_bytes = body_size
        ingestion.expected_raw_parts = expected_raw_parts
        ingestion.raw_status = raw_status
        ingestion.device_id = payload.device_id
        ingestion.started_at = payload.started_at
        ingestion.ended_at = payload.ended_at
        ingestion.core_status = TripIngestion.PhaseStatus.PROCESSING
        ingestion.started_processing_at = now
        ingestion.error_message = ""
        ingestion.save(
            update_fields=[
                "core_payload_size_bytes",
                "expected_raw_parts",
                "raw_status",
                "device_id",
                "started_at",
                "ended_at",
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

        # Replay
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

        return ingestion

"""
Mette in coda il job che analizza i dati raw
"""
def queue_final_har(ingestion: TripIngestion, *, now: datetime) -> None:
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
    job = HarJob.objects.create(trip_id=ingestion.trip_id)
    from ..tasks import process_trip_har_final

    transaction.on_commit(lambda: process_trip_har_final.delay(job.id, ingestion.id))


""" 
Funzione che ottiene il lock sulla trip ingestion interrogata, se non esiste solleva IngestionNotFound
"""
def _locked_owned_ingestion(user_id: int, ingestion_id: int) -> TripIngestion:
    ingestion = (
        TripIngestion.objects.filter(user_id=user_id, id=ingestion_id)
        .select_for_update()
        .first()
    )
    if ingestion is None:
        raise IngestionNotFound("ingestion non trovata")
    return ingestion

"""
Recupera la trip ingestion creata al momento dello start ed esegue dei controlli di sicurezza
"""
def _get_inline_core_ingestion(
    *,
    user_id: int,
    payload,
    expected_raw_parts: int,
    raw_status: str,
    body_size: int,
) -> TripIngestion:
    ingestion = _locked_owned_ingestion(user_id, payload.ingestion_id)
    if ingestion.client_session_id != payload.client_session_id:
        raise IngestionServiceError("client_session_id non corrisponde")
    if ingestion.device_id != payload.device_id:
        raise IngestionForbidden("device_id non autorizzato")
    if ingestion.recording_started_at is None:
        raise IngestionServiceError("viaggio non avviato")
    return ingestion


def _active_last_seen(ingestion: TripIngestion) -> datetime:
    return (
        ingestion.last_seen_at
        or ingestion.recording_started_at
        or ingestion.created_at
    )


"""
Controlla se la trip ingestion interrogata è attiva da pià di 24 ore, se lo è
segnala come abbandonata
"""
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


"""
Funzione che controlla, nel caso in cui siamo in una registrazione in modalità replay
Se il viaggio già esistente è ricaricabile oppure no
"""
def _validate_source_trip(user_id: int, source_trip_id: int | None) -> int | None:
    if source_trip_id is None:
        return None
    if not Trip.objects.filter(
        id=source_trip_id,
        user_id=user_id,
        is_reloadable=True,
        status__in=[Trip.Status.CLOSED, Trip.Status.PROCESSED],
    ).exists():
        raise IngestionUnprocessable("viaggio sorgente non ricaricabile")
    return source_trip_id

"""
Funzione di sicurezza, controllo se lo slot temporale dove voglio inserire un viaggio non si
sovrappoine con altri viaggi
"""
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
