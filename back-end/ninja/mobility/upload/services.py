from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta

from django.conf import settings
from django.db import transaction
from django.utils import timezone

from shared.exceptions import ServiceError

from ..models import TripUpload, TripUploadPart
from ..replay_raw import (
    ReplayRawError,
    ReplayStorageUnavailable,
    regenerate_raw_and_queue_har,
)
from ..selectors import har_jobs as har_jobs_repository
from ..selectors import trips as trips_repository
from ..tasks import process_trip_har_final
from . import selectors as upload_repository
from . import storage
from .materialization import (
    CoreMaterializationConflict,
    materialize_inline_core_upload,
)
from .selectors import locked_active_uploads_for_owner

ACTIVE_UPLOAD_STALE_AFTER = timedelta(hours=24)


class UploadServiceError(ServiceError):
    status_code = 409


class UploadNotFound(UploadServiceError):
    status_code = 404


class UploadForbidden(UploadServiceError):
    status_code = 403


class UploadGone(UploadServiceError):
    status_code = 410


class UploadBadRequest(UploadServiceError):
    status_code = 400


class UploadUnprocessable(UploadServiceError):
    status_code = 422


class UploadStorageUnavailable(UploadServiceError):
    status_code = 503


class UploadPartMismatch(UploadServiceError):
    status_code = 409


@dataclass(frozen=True)
class StartRecordingResult:
    upload: TripUpload
    already_exists: bool = False
    conflict_upload: TripUpload | None = None


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
        active = locked_active_uploads_for_owner(user_id).first()
        if active is not None:
            if not _abandon_if_stale(active, now=now):
                if (
                    active.client_session_id == client_session_id
                    and active.device_id == device_id
                ):
                    return StartRecordingResult(active, already_exists=True)
                return StartRecordingResult(active, conflict_upload=active)

        upload = upload_repository.create_upload(
            user_id=user_id,
            client_session_id=client_session_id,
            device_id=device_id,
            started_at=recording_started_at,
            recording_started_at=recording_started_at,
            last_seen_at=now,
            source_trip_id=source_trip_id,
        )
        if not upload.raw_base_path:
            upload.raw_base_path = f"uploads/{upload.id}/"
            upload.save(update_fields=["raw_base_path", "updated_at"])
        return StartRecordingResult(upload)


def active_recording_for_user(
    user_id: int,
    *,
    now: datetime | None = None,
) -> TripUpload | None:
    now = now or timezone.now()
    with transaction.atomic():
        upload = locked_active_uploads_for_owner(user_id).first()
        if upload is None or _abandon_if_stale(upload, now=now):
            return None
        return upload


"""
Funzione che aggiorna il last_seen_at della trip upload interrogata anche se non è più vecchia d 24 ore
"""
def heartbeat_recording(
    *,
    user_id: int,
    upload_id: int,
    client_session_id: str,
    device_id: str,
    now: datetime | None = None,
) -> TripUpload:
    now = now or timezone.now()
    with transaction.atomic():
        upload = _locked_owned_upload(user_id, upload_id)
        if upload.client_session_id != client_session_id:
            raise UploadServiceError("client_session_id non corrisponde")
        if upload.device_id != device_id:
            raise UploadForbidden("device_id non autorizzato")
        if (
            upload.recording_abandoned_at is not None
            or upload.recording_closed_at is not None
        ):
            raise UploadGone("viaggio non piu' in corso")
        upload.last_seen_at = now
        upload.save(update_fields=["last_seen_at", "updated_at"])
        
        return upload

"""
Funzione che chiude la trip upload interrogata, segnando il recording_closed_at
"""
def abandon_recording(
    *,
    user_id: int,
    upload_id: int,
    device_id: str,
    now: datetime | None = None,
) -> TripUpload:
    now = now or timezone.now()
    with transaction.atomic():
        upload = _locked_owned_upload(user_id, upload_id)
        if upload.device_id != device_id:
            raise UploadForbidden("solo il dispositivo origine puo' abbandonare")
        if upload.recording_closed_at is not None:
            raise UploadServiceError("viaggio gia' chiuso")
        if upload.recording_abandoned_at is None:
            upload.recording_abandoned_at = now
            upload.save(update_fields=["recording_abandoned_at", "updated_at"])
        return upload



def validate_expected_parts(count: int) -> int:
    normalized_count = int(count or 0)
    if normalized_count < 0:
        raise UploadUnprocessable("expected_raw_parts contiene count non valido")
    return normalized_count


"""
Funzione che esegue tutta la fase di caricamento core del viaggio
"""
def process_inline_core_upload(
    user_id: int,
    payload,
    expected_raw_parts: int,
    raw_status: str,
) -> TripUpload:
    payload = _normalize_and_validate_core_timeline(payload)
    with transaction.atomic():
        upload = _get_inline_core_upload(
            user_id=user_id,
            payload=payload,
            expected_raw_parts=expected_raw_parts,
            raw_status=raw_status,
        )
        
        if not upload.raw_base_path:
            upload.raw_base_path = f"uploads/{upload.id}/"
            upload.save(update_fields=["raw_base_path", "updated_at"])

        now = timezone.now()
        upload.expected_raw_parts = expected_raw_parts
        upload.raw_status = raw_status
        upload.device_id = payload.device_id
        upload.started_at = payload.started_at
        upload.ended_at = payload.ended_at
        upload.core_status = TripUpload.PhaseStatus.PROCESSING
        upload.started_processing_at = now
        upload.error_message = ""
        upload.save(
            update_fields=[
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

        if upload.source_trip_id is not None:
            _validate_replay_slot(
                user_id=user_id,
                client_session_id=upload.client_session_id,
                started_at=payload.started_at,
                ended_at=payload.ended_at,
            )

        try:
            materialized = materialize_inline_core_upload(upload, payload)
        except CoreMaterializationConflict as exc:
            raise UploadServiceError(str(exc)) from exc
        trip = materialized.trip
        trip.refresh_from_db(fields=["distance_meters", "path"])

        upload.trip = trip
        upload.core_status = TripUpload.PhaseStatus.COMPLETED
        upload.completed_at = now
        upload.failed_at = None
        if payload.upload_id is not None:
            upload.recording_closed_at = payload.ended_at or now
            upload.last_seen_at = now
        update_fields = [
            "trip",
            "core_status",
            "completed_at",
            "failed_at",
            "updated_at",
        ]
        if payload.upload_id is not None:
            update_fields.extend(["recording_closed_at", "last_seen_at"])
        upload.save(update_fields=update_fields)

        # Replay
        if upload.source_trip_id is not None:
            if payload.cutoff_source_timestamp is None:
                raise UploadBadRequest(
                    "cutoff_source_timestamp richiesto per il replay"
                )
            ended_at = upload.recording_closed_at or now
            try:
                regenerate_raw_and_queue_har(
                    upload,
                    upload.source_trip,
                    shift=ended_at - payload.cutoff_source_timestamp,
                    now=now,
                    cutoff=payload.cutoff_source_timestamp,
                )
            except ReplayStorageUnavailable as exc:
                raise UploadStorageUnavailable(exc.message) from exc
            except ReplayRawError as exc:
                raise UploadServiceError(exc.message) from exc

        return upload


def _normalize_and_validate_core_timeline(payload):
    started_at = payload.started_at
    ended_at = payload.ended_at
    if started_at is not None and ended_at is not None and ended_at < started_at:
        raise UploadUnprocessable("ended_at precedente a started_at")

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
        raise UploadUnprocessable("evidenza successiva a ended_at")
    if not gps_points and not state_transitions:
        raise UploadBadRequest(
            "core vuoto: nessuna evidenza interna all'intervallo del viaggio"
        )
    return payload.model_copy(
        update={
            "gps_points": gps_points,
            "state_transitions": state_transitions,
        }
    )

"""
Mette in coda il job che analizza i dati raw e 
"""
def queue_final_har(upload: TripUpload, *, now: datetime) -> None:
    upload.raw_status = TripUpload.PhaseStatus.QUEUED
    upload.queued_at = now
    upload.error_message = ""
    upload.save(
        update_fields=[
            "raw_status",
            "queued_at",
            "error_message",
            "updated_at",
        ]
    )
    job = har_jobs_repository.create_har_job(upload.trip_id)
    transaction.on_commit(lambda: process_trip_har_final.delay(job.id, upload.id))

def _raw_part_count(parts: object) -> int:
    if isinstance(parts, dict):
        return int(next(iter(parts.values()), 0) or 0)
    return int(parts or 0)


def _expected_part_sequences(parts: object) -> list[int]:
    count = _raw_part_count(parts)
    return list(range(1, count + 1))


def _confirmed_raw_sequences(upload: TripUpload) -> set[int]:
    return {
        seq
        for seq in upload.parts.filter(
            received_at__isnull=False,
        ).values_list("sequence", flat=True)
    }


def missing_raw_parts(upload: TripUpload) -> list[dict[str, int]]:
    confirmed = _confirmed_raw_sequences(upload)
    expected = _expected_part_sequences(upload.expected_raw_parts)
    return [{"sequence": seq} for seq in expected if seq not in confirmed]


def _mark_raw_received_if_complete(upload: TripUpload) -> None:
    expected = _expected_part_sequences(upload.expected_raw_parts)
    if not expected:
        return
    confirmed = _confirmed_raw_sequences(upload)
    if all(sequence in confirmed for sequence in expected):
        if upload.raw_status == TripUpload.PhaseStatus.RECEIVING:
            upload.raw_status = TripUpload.PhaseStatus.RECEIVED
            upload.save(update_fields=["raw_status", "updated_at"])


def owned_upload_or_error(user_id: int, upload_id: int) -> TripUpload:
    upload = upload_repository.owned_upload(user_id, upload_id)
    if upload is None:
        raise UploadNotFound("upload non trovata")
    return upload


@dataclass(frozen=True)
class PartPresignResult:
    object_key: str
    upload_url: str
    upload_headers: dict[str, str]
    expires_in: int



def presign_raw_part(
    *,
    user_id: int,
    upload_id: int,
    sequence: int,
    sha256: str,
) -> PartPresignResult:
    upload = owned_upload_or_error(user_id, upload_id)
    object_key = storage.raw_part_object_key(upload.raw_base_path, sequence)

    with transaction.atomic():
        upload_repository.get_or_create_upload_part(
            upload,
            sequence=sequence,
            defaults={
                "sha256": sha256,
                "object_key": object_key,
            },
        )
        if upload.raw_status == TripUpload.PhaseStatus.PENDING:
            upload.raw_status = TripUpload.PhaseStatus.RECEIVING
            upload.save(update_fields=["raw_status", "updated_at"])

    upload_url = storage.presigned_put_url(object_key, sha256=sha256)
    return PartPresignResult(
        object_key=object_key,
        upload_url=upload_url,
        upload_headers={
            "Content-Type": "application/gzip",
            # Deve essere lo stesso valore firmato dentro upload_url: S3
            # confronta questo header con l'hash reale dei byte ricevuti e
            # rifiuta l'upload se non torna.
            "x-amz-checksum-sha256": storage.checksum_header_value(sha256),
        },
        expires_in=settings.S3_PRESIGN_EXPIRES_SECONDS,
    )


"""
Conferma la ricezione di una parte raw gia' presignata. L'integrita' del
contenuto e' gia' garantita da S3/MinIO stesso (ha rifiutato l'upload se il
checksum non corrispondeva ai byte ricevuti): qui controlliamo solo che
l'oggetto ci sia davvero e porti il checksum atteso per QUESTA parte, poi
segniamo la parte come ricevuta e valutiamo se la fase raw e' completa.
"""
def confirm_raw_part(
    *,
    user_id: int,
    upload_id: int,
    sequence: int,
    sha256: str,
    now: datetime | None = None,
) -> TripUploadPart:
    now = now or timezone.now()
    upload = owned_upload_or_error(user_id, upload_id)
    part = upload_repository.upload_part_by_sequence(upload, sequence)
    if part is None:
        raise UploadNotFound("parte non trovata")

    if part.sha256 != sha256:
        raise UploadPartMismatch(
            "checksum non corrisponde a quello dichiarato in presign"
        )

    head = storage.head_object(part.object_key)
    if head is None:
        raise UploadPartMismatch("oggetto non presente sullo storage")
    # ChecksumSHA256 e' verificato da S3/MinIO stesso al momento dell'upload:
    # se il valore letto qui e' presente, i byte sono per forza integri.
    stored_checksum = head.get("ChecksumSHA256")
    if stored_checksum != storage.checksum_header_value(part.sha256):
        raise UploadPartMismatch("checksum sha256 non corrisponde")

    upload_repository.mark_part_received(part, received_at=now)
    _mark_raw_received_if_complete(upload)
    return part


"""
Controlli ulteriori e  fa partire il job asincrono
"""
def complete_raw_upload(
    *,
    user_id: int,
    upload_id: int,
    total_parts: int | None,
    now: datetime | None = None,
) -> TripUpload:
    now = now or timezone.now()
    with transaction.atomic():
        upload = upload_repository.locked_owned_upload(user_id, upload_id)
        if upload is None:
            raise UploadNotFound("upload non trovata")
        if upload.raw_status == TripUpload.PhaseStatus.FAILED_FINAL:
            raise UploadServiceError("raw sensor upload fallita definitivamente")
        if (
            upload.core_status != TripUpload.PhaseStatus.COMPLETED
            or upload.trip_id is None
        ):
            raise UploadServiceError("core upload non completata")
        if (
            total_parts is not None
            and total_parts != _raw_part_count(upload.expected_raw_parts)
        ):
            raise UploadServiceError("numero parti raw diverso dal manifest iniziale")
        missing = missing_raw_parts(upload)
        if missing:
            sequences = ", ".join(str(part["sequence"]) for part in missing)
            raise UploadPartMismatch(f"parti raw mancanti: {sequences}")

        queue_final_har(upload, now=now)
    return upload


"""
Funzione che ottiene il lock sulla trip upload interrogata, se non esiste solleva UploadNotFound
"""
def _locked_owned_upload(user_id: int, upload_id: int) -> TripUpload:
    upload = upload_repository.locked_owned_upload(user_id, upload_id)
    if upload is None:
        raise UploadNotFound("upload non trovata")
    return upload

"""
Recupera la trip upload creata al momento dello start ed esegue dei controlli di sicurezza
"""
def _get_inline_core_upload(
    *,
    user_id: int,
    payload,
    expected_raw_parts: int,
    raw_status: str,
) -> TripUpload:
    upload = _locked_owned_upload(user_id, payload.upload_id)
    if upload.client_session_id != payload.client_session_id:
        raise UploadServiceError("client_session_id non corrisponde")
    if upload.device_id != payload.device_id:
        raise UploadForbidden("device_id non autorizzato")
    if upload.recording_started_at is None:
        raise UploadServiceError("viaggio non avviato")
    if upload.recording_abandoned_at is not None:
        raise UploadGone("viaggio abbandonato")
    return upload


def _active_last_seen(upload: TripUpload) -> datetime:
    return (
        upload.last_seen_at
        or upload.recording_started_at
        or upload.created_at
    )


"""
Controlla se la trip upload interrogata è attiva da pià di 24 ore, se lo è
segnala come abbandonata
"""
def _abandon_if_stale(
    upload: TripUpload,
    *,
    now: datetime,
) -> bool:
    if now - _active_last_seen(upload) < ACTIVE_UPLOAD_STALE_AFTER:
        return False
    upload.recording_abandoned_at = now
    upload.save(update_fields=["recording_abandoned_at", "updated_at"])
    return True


"""
Funzione che controlla, nel caso in cui siamo in una registrazione in modalità replay
Se il viaggio già esistente è ricaricabile oppure no
"""
def _validate_source_trip(user_id: int, source_trip_id: int | None) -> int | None:
    if source_trip_id is None:
        return None
    if not trips_repository.reloadable_source_trip_exists(source_trip_id, user_id):
        raise UploadUnprocessable("viaggio sorgente non ricaricabile")
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
        raise UploadServiceError("scegli uno slot nel passato")
    overlaps = trips_repository.trip_overlaps_window(
        user_id,
        start=started_at,
        end=ended_at,
        exclude_client_session_id=client_session_id,
    )
    if overlaps:
        raise UploadServiceError("slot sovrapposto a un viaggio esistente")
