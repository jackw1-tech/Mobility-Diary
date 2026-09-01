from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta

from django.conf import settings
from django.db import transaction
from django.utils import timezone

from shared.exceptions import ServiceError

from ..models import TripIngestion, TripIngestionPart
from ..replay_raw import (
    ReplayRawError,
    ReplayStorageUnavailable,
    regenerate_raw_and_queue_har,
)
from ..selectors import har_jobs as har_jobs_repository
from ..selectors import trips as trips_repository
from ..tasks import process_trip_har_final
from . import selectors as ingestion_repository
from . import storage
from .materialization import (
    CoreMaterializationConflict,
    materialize_inline_core_ingestion,
)
from .selectors import locked_active_ingestions_for_owner

ACTIVE_INGESTION_STALE_AFTER = timedelta(hours=24)


class IngestionServiceError(ServiceError):
    status_code = 409


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


class IngestionPartNotDeclared(IngestionServiceError):
    status_code = 409


class IngestionStorageUnavailable(IngestionServiceError):
    status_code = 503


class IngestionPartMismatch(IngestionServiceError):
    status_code = 409


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

        ingestion = ingestion_repository.create_ingestion(
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


def active_recording_for_user(
    user_id: int,
    *,
    now: datetime | None = None,
) -> TripIngestion | None:
    now = now or timezone.now()
    with transaction.atomic():
        ingestion = locked_active_ingestions_for_owner(user_id).first()
        if ingestion is None or _abandon_if_stale(ingestion, now=now):
            return None
        return ingestion


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
        if (
            ingestion.recording_abandoned_at is not None
            or ingestion.recording_closed_at is not None
        ):
            raise IngestionGone("viaggio non piu' in corso")
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



def validate_expected_parts(count: int) -> int:
    normalized_count = int(count or 0)
    if normalized_count < 0:
        raise IngestionUnprocessable("expected_raw_parts contiene count non valido")
    return normalized_count


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
    payload = _normalize_and_validate_core_timeline(payload)
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
            try:
                regenerate_raw_and_queue_har(
                    ingestion,
                    ingestion.source_trip,
                    shift=ended_at - payload.cutoff_source_timestamp,
                    now=now,
                    cutoff=payload.cutoff_source_timestamp,
                )
            except ReplayStorageUnavailable as exc:
                raise IngestionStorageUnavailable(exc.message) from exc
            except ReplayRawError as exc:
                raise IngestionServiceError(exc.message) from exc

        return ingestion


def _normalize_and_validate_core_timeline(payload):
    started_at = payload.started_at
    ended_at = payload.ended_at
    if started_at is not None and ended_at is not None and ended_at < started_at:
        raise IngestionUnprocessable("ended_at precedente a started_at")

    gps_points = payload.gps_points
    state_transitions = payload.state_transitions
    if started_at is not None:
        gps_points = [
            point for point in gps_points if point.timestamp >= started_at
        ]
        state_transitions = [
            transition
            for transition in state_transitions
            if transition.timestamp >= started_at
        ]

    evidence_timestamps = [point.timestamp for point in gps_points]
    evidence_timestamps.extend(
        transition.timestamp for transition in state_transitions
    )
    if ended_at is not None and any(
        timestamp > ended_at for timestamp in evidence_timestamps
    ):
        raise IngestionUnprocessable("evidenza successiva a ended_at")
    if not gps_points and not state_transitions:
        raise IngestionBadRequest(
            "core vuoto: nessuna evidenza interna all'intervallo del viaggio"
        )
    return payload.model_copy(
        update={
            "gps_points": gps_points,
            "state_transitions": state_transitions,
        }
    )

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
    job = har_jobs_repository.create_har_job(ingestion.trip_id)
    transaction.on_commit(lambda: process_trip_har_final.delay(job.id, ingestion.id))


def _object_key(base_path: str, sequence: int) -> str:
    return f"{base_path}sensor_windows_part_{sequence:04d}.bin.gz"


def _raw_part_count(parts: object) -> int:
    if isinstance(parts, dict):
        return int(next(iter(parts.values()), 0) or 0)
    return int(parts or 0)


def _expected_part_sequences(parts: object) -> list[int]:
    count = _raw_part_count(parts)
    return list(range(1, count + 1))


def _confirmed_raw_sequences(ingestion: TripIngestion) -> set[int]:
    return {
        seq
        for seq in ingestion.parts.filter(
            received_at__isnull=False,
        ).values_list("sequence", flat=True)
    }


def missing_raw_parts(ingestion: TripIngestion) -> list[dict[str, int]]:
    confirmed = _confirmed_raw_sequences(ingestion)
    expected = _expected_part_sequences(ingestion.expected_raw_parts)
    return [{"sequence": seq} for seq in expected if seq not in confirmed]


def _mark_raw_received_if_complete(ingestion: TripIngestion) -> None:
    expected = _expected_part_sequences(ingestion.expected_raw_parts)
    if not expected:
        return
    confirmed = _confirmed_raw_sequences(ingestion)
    if all(sequence in confirmed for sequence in expected):
        if ingestion.raw_status == TripIngestion.PhaseStatus.RECEIVING:
            ingestion.raw_status = TripIngestion.PhaseStatus.RECEIVED
            ingestion.save(update_fields=["raw_status", "updated_at"])


def _ensure_part_was_declared(ingestion: TripIngestion, sequence: int) -> None:
    expected_count = _raw_part_count(ingestion.expected_raw_parts)
    if sequence < 1 or sequence > expected_count:
        raise IngestionPartNotDeclared(
            f"parte non dichiarata nel manifest iniziale: #{sequence}"
        )


def owned_ingestion_or_error(user_id: int, ingestion_id: int) -> TripIngestion:
    ingestion = ingestion_repository.owned_ingestion(user_id, ingestion_id)
    if ingestion is None:
        raise IngestionNotFound("ingestion non trovata")
    return ingestion


@dataclass(frozen=True)
class PartPresignResult:
    object_key: str
    upload_url: str
    upload_headers: dict[str, str]
    expires_in: int


"""
Dichiara e presigna una parte raw: valida la dimensione e che la sequenza sia
stata annunciata nel manifest iniziale, poi apre la fase RECEIVING alla prima
parte ricevuta.
"""
def presign_raw_part(
    *,
    user_id: int,
    ingestion_id: int,
    sequence: int,
    sha256: str,
    size_bytes: int,
) -> PartPresignResult:
    if size_bytes <= 0 or size_bytes > settings.INGESTION_MAX_PART_BYTES:
        raise IngestionUnprocessable(
            f"size_bytes fuori range (max {settings.INGESTION_MAX_PART_BYTES})"
        )

    ingestion = owned_ingestion_or_error(user_id, ingestion_id)
    _ensure_part_was_declared(ingestion, sequence)
    object_key = _object_key(ingestion.raw_base_path, sequence)

    with transaction.atomic():
        ingestion_repository.get_or_create_ingestion_part(
            ingestion,
            sequence=sequence,
            defaults={
                "sha256": sha256,
                "size_bytes": size_bytes,
                "object_key": object_key,
            },
        )
        if ingestion.raw_status == TripIngestion.PhaseStatus.PENDING:
            ingestion.raw_status = TripIngestion.PhaseStatus.RECEIVING
            ingestion.save(update_fields=["raw_status", "updated_at"])

    upload_url = storage.presigned_put_url(object_key, sha256=sha256)
    return PartPresignResult(
        object_key=object_key,
        upload_url=upload_url,
        upload_headers={
            "Content-Type": "application/gzip",
            "x-amz-meta-sha256": sha256,
        },
        expires_in=settings.S3_PRESIGN_EXPIRES_SECONDS,
    )


"""
Conferma la ricezione di una parte raw gia' presignata: verifica il checksum
dichiarato contro quello effettivamente salvato sullo storage, poi segna la
parte come ricevuta e valuta se la fase raw e' completa.
"""
def confirm_raw_part(
    *,
    user_id: int,
    ingestion_id: int,
    sequence: int,
    sha256: str,
    now: datetime | None = None,
) -> TripIngestionPart:
    now = now or timezone.now()
    ingestion = owned_ingestion_or_error(user_id, ingestion_id)
    part = ingestion_repository.ingestion_part_by_sequence(ingestion, sequence)
    if part is None:
        raise IngestionNotFound("parte non trovata")

    if part.sha256 != sha256:
        raise IngestionPartMismatch(
            "checksum non corrisponde a quello dichiarato in presign"
        )

    head = storage.head_object(part.object_key)
    if head is None:
        raise IngestionPartMismatch("oggetto non presente sullo storage")
    metadata_sha256 = (head.get("Metadata") or {}).get("sha256")
    if metadata_sha256 != part.sha256:
        raise IngestionPartMismatch("sha256 metadata non corrisponde")

    ingestion_repository.mark_part_received(part, received_at=now)
    _mark_raw_received_if_complete(ingestion)
    return part


"""
Chiude la fase raw dell'ingestion e accoda l'HAR finale, dopo aver verificato
che non sia gia' fallita definitivamente e che il conteggio parti dichiarato
dal client combaci col manifest iniziale.
"""
def complete_raw_ingestion(
    *,
    user_id: int,
    ingestion_id: int,
    total_parts: int | None,
    now: datetime | None = None,
) -> TripIngestion:
    now = now or timezone.now()
    with transaction.atomic():
        ingestion = ingestion_repository.locked_owned_ingestion(user_id, ingestion_id)
        if ingestion is None:
            raise IngestionNotFound("ingestion non trovata")
        if ingestion.raw_status == TripIngestion.PhaseStatus.FAILED_FINAL:
            raise IngestionServiceError("raw sensor ingestion fallita definitivamente")
        if (
            ingestion.core_status != TripIngestion.PhaseStatus.COMPLETED
            or ingestion.trip_id is None
        ):
            raise IngestionServiceError("core ingestion non completata")
        if (
            total_parts is not None
            and total_parts != _raw_part_count(ingestion.expected_raw_parts)
        ):
            raise IngestionServiceError("numero parti raw diverso dal manifest iniziale")
        missing = missing_raw_parts(ingestion)
        if missing:
            sequences = ", ".join(f"#{part['sequence']}" for part in missing)
            raise IngestionServiceError(f"parti raw mancanti: {sequences}")

        queue_final_har(ingestion, now=now)
    return ingestion


"""
Funzione che ottiene il lock sulla trip ingestion interrogata, se non esiste solleva IngestionNotFound
"""
def _locked_owned_ingestion(user_id: int, ingestion_id: int) -> TripIngestion:
    ingestion = ingestion_repository.locked_owned_ingestion(user_id, ingestion_id)
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
    if ingestion.recording_abandoned_at is not None:
        raise IngestionGone("viaggio abbandonato")
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
    if not trips_repository.reloadable_source_trip_exists(source_trip_id, user_id):
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
    overlaps = trips_repository.trip_overlaps_window(
        user_id,
        start=started_at,
        end=ended_at,
        exclude_client_session_id=client_session_id,
    )
    if overlaps:
        raise IngestionServiceError("slot sovrapposto a un viaggio esistente")
