"""API di ingestione asincrona dei viaggi.

Upload "stupido" e affidabile: il backend non riceve mai i byte pesanti, genera
presigned URL e tiene la contabilita' delle parti. Il processing (materializzazione
Trip + HAR) e' demandato a Celery (REPORT_STRATEGIA_INGESTION_ASINCRONA.md).

Flusso: create -> presign (N) -> PUT diretto su storage -> confirm (N) -> complete.
"""
from __future__ import annotations

from django.conf import settings
from django.db import transaction
from django.shortcuts import get_object_or_404
from django.utils import timezone
from ninja import Router
from ninja.errors import HttpError

from accounts.auth import mobile_bearer_auth

from ..models import PartKind, TripIngestion, TripIngestionPart
from . import storage
from .schemas import (
    CompleteIn,
    CompleteOut,
    IngestionCreateIn,
    IngestionCreateOut,
    IngestionStatusOut,
    PartConfirmIn,
    PartConfirmOut,
    PartPresignIn,
    PartPresignOut,
)

router = Router(tags=["ingestion"])

_VALID_KINDS = set(PartKind.values)
# Stati in cui si possono ancora ricevere/confermare parti.
_RECEIVING_STATES = {
    TripIngestion.Status.CREATED,
    TripIngestion.Status.RECEIVING,
    TripIngestion.Status.READY_TO_PROCESS,
}


def _object_key(base_path: str, kind: str, sequence: int) -> str:
    if kind == PartKind.SENSOR_WINDOWS:
        return f"{base_path}sensor_windows_part_{sequence:04d}.json.gz"
    return f"{base_path}{kind}.json.gz"


def _expected_part_keys(ingestion: TripIngestion) -> list[tuple[str, int]]:
    expected: list[tuple[str, int]] = []
    for kind, count in (ingestion.expected_parts or {}).items():
        for sequence in range(1, int(count) + 1):
            expected.append((kind, sequence))
    return expected


def _get_owned_ingestion(request, ingestion_id: int) -> TripIngestion:
    return get_object_or_404(
        TripIngestion, id=ingestion_id, user_id=request.auth.user_id
    )


def _validate_kind(kind: str) -> None:
    if kind not in _VALID_KINDS:
        raise HttpError(422, f"kind non valido: {kind}")


@router.post("/trips", response=IngestionCreateOut, auth=mobile_bearer_auth)
def create_ingestion(request, payload: IngestionCreateIn):
    user_id = request.auth.user_id
    ingestion, created = TripIngestion.objects.get_or_create(
        user_id=user_id,
        client_session_id=payload.client_session_id,
        defaults={
            "device_id": payload.device_id,
            "schema_version": payload.schema_version,
            "expected_parts": payload.expected_parts,
            "started_at": payload.started_at,
            "ended_at": payload.ended_at,
            "timezone": payload.timezone,
            "app_version": payload.app_version,
            "device_platform": payload.device_platform,
        },
    )
    if not ingestion.raw_base_path:
        ingestion.raw_base_path = f"ingestions/{ingestion.id}/"
        ingestion.save(update_fields=["raw_base_path", "updated_at"])

    return IngestionCreateOut(
        ingestion_id=ingestion.id,
        status=ingestion.status,
        already_exists=not created,
    )


@router.post(
    "/trips/{ingestion_id}/parts/presign",
    response=PartPresignOut,
    auth=mobile_bearer_auth,
)
def presign_part(request, ingestion_id: int, payload: PartPresignIn):
    _validate_kind(payload.kind)
    if payload.size_bytes <= 0 or payload.size_bytes > settings.INGESTION_MAX_PART_BYTES:
        raise HttpError(
            422,
            f"size_bytes fuori range (max {settings.INGESTION_MAX_PART_BYTES})",
        )

    ingestion = _get_owned_ingestion(request, ingestion_id)
    if ingestion.status not in _RECEIVING_STATES:
        raise HttpError(409, f"ingestion in stato {ingestion.status}, upload non ammesso")

    object_key = _object_key(ingestion.raw_base_path, payload.kind, payload.sequence)

    with transaction.atomic():
        part, _ = TripIngestionPart.objects.select_for_update().get_or_create(
            ingestion=ingestion,
            kind=payload.kind,
            sequence=payload.sequence,
            defaults={
                "sha256": payload.sha256,
                "size_bytes": payload.size_bytes,
                "object_key": object_key,
            },
        )
        # Se la parte e' gia' stata confermata con un checksum diverso e' un conflitto.
        if part.received_at is not None and part.sha256 != payload.sha256:
            raise HttpError(409, "parte gia' ricevuta con checksum diverso")
        # Non ancora confermata: aggiorna i metadati dichiarati (re-packaging).
        if part.received_at is None:
            part.sha256 = payload.sha256
            part.size_bytes = payload.size_bytes
            part.object_key = object_key
            part.save(update_fields=["sha256", "size_bytes", "object_key"])

        if ingestion.status == TripIngestion.Status.CREATED:
            ingestion.status = TripIngestion.Status.RECEIVING
            ingestion.save(update_fields=["status", "updated_at"])

    upload_headers = {
        "Content-Type": "application/gzip",
        "x-amz-meta-sha256": payload.sha256,
    }
    upload_url = storage.presigned_put_url(object_key, sha256=payload.sha256)
    return PartPresignOut(
        object_key=object_key,
        upload_url=upload_url,
        upload_headers=upload_headers,
        expires_in=settings.S3_PRESIGN_EXPIRES_SECONDS,
    )


@router.post(
    "/trips/{ingestion_id}/parts/confirm",
    response=PartConfirmOut,
    auth=mobile_bearer_auth,
)
def confirm_part(request, ingestion_id: int, payload: PartConfirmIn):
    _validate_kind(payload.kind)
    ingestion = _get_owned_ingestion(request, ingestion_id)
    part = get_object_or_404(
        TripIngestionPart,
        ingestion=ingestion,
        kind=payload.kind,
        sequence=payload.sequence,
    )

    if part.sha256 != payload.sha256:
        raise HttpError(409, "checksum non corrisponde a quello dichiarato in presign")

    # Idempotente: se gia' confermata, non rifare la HEAD.
    if part.received_at is not None:
        return PartConfirmOut(
            ingestion_id=ingestion.id,
            kind=part.kind,
            sequence=part.sequence,
            status="ALREADY_RECEIVED",
        )

    # Verifica via HEAD che il blob sia davvero arrivato, senza scaricare i byte.
    head = storage.head_object(part.object_key)
    if head is None:
        raise HttpError(409, "oggetto non presente sullo storage")
    actual_size = head.get("ContentLength", 0)
    if part.size_bytes and actual_size != part.size_bytes:
        raise HttpError(
            409,
            f"dimensione non corrisponde (attesa {part.size_bytes}, trovata {actual_size})",
        )
    metadata_sha256 = (head.get("Metadata") or {}).get("sha256")
    if metadata_sha256 != part.sha256:
        raise HttpError(409, "sha256 metadata non corrisponde")

    part.received_at = timezone.now()
    part.save(update_fields=["received_at"])
    return PartConfirmOut(
        ingestion_id=ingestion.id,
        kind=part.kind,
        sequence=part.sequence,
        status="RECEIVED",
    )


@router.post(
    "/trips/{ingestion_id}/complete", response={202: CompleteOut}, auth=mobile_bearer_auth
)
def complete_ingestion(request, ingestion_id: int, payload: CompleteIn):
    ingestion = _get_owned_ingestion(request, ingestion_id)

    # Idempotente: se gia' in coda o oltre, non rifare nulla.
    if ingestion.status in {
        TripIngestion.Status.QUEUED,
        TripIngestion.Status.PROCESSING,
        TripIngestion.Status.PROCESSED,
        TripIngestion.Status.COMPLETED,
        TripIngestion.Status.FAILED_RETRYABLE,
    }:
        return 202, CompleteOut(ingestion_id=ingestion.id, status=ingestion.status)
    if ingestion.status == TripIngestion.Status.FAILED_FINAL:
        raise HttpError(409, "ingestion fallita definitivamente")

    confirmed = {
        (kind, seq)
        for kind, seq in ingestion.parts.filter(received_at__isnull=False).values_list(
            "kind", "sequence"
        )
    }
    missing = [pk for pk in _expected_part_keys(ingestion) if pk not in confirmed]
    if missing:
        readable = ", ".join(f"{kind}#{seq}" for kind, seq in missing)
        raise HttpError(409, f"parti mancanti: {readable}")

    with transaction.atomic():
        ingestion.manifest_sha256 = payload.manifest_sha256
        ingestion.status = TripIngestion.Status.QUEUED
        ingestion.queued_at = timezone.now()
        ingestion.save(update_fields=["manifest_sha256", "status", "queued_at", "updated_at"])

    # Import locale: evita import circolare e accoppiamento a Celery a load-time.
    from ..tasks import process_trip_ingestion

    transaction.on_commit(lambda: process_trip_ingestion.delay(ingestion.id))
    return 202, CompleteOut(ingestion_id=ingestion.id, status=ingestion.status)


@router.get(
    "/trips/{ingestion_id}", response=IngestionStatusOut, auth=mobile_bearer_auth
)
def ingestion_status(request, ingestion_id: int):
    ingestion = _get_owned_ingestion(request, ingestion_id)

    confirmed = {
        (kind, seq)
        for kind, seq in ingestion.parts.filter(received_at__isnull=False).values_list(
            "kind", "sequence"
        )
    }
    expected = _expected_part_keys(ingestion)
    received_parts = [
        {"kind": kind, "sequence": seq} for kind, seq in expected if (kind, seq) in confirmed
    ]
    missing_parts = [
        {"kind": kind, "sequence": seq} for kind, seq in expected if (kind, seq) not in confirmed
    ]
    progress = round(100 * len(received_parts) / len(expected)) if expected else 0

    return IngestionStatusOut(
        ingestion_id=ingestion.id,
        status=ingestion.status,
        received_parts=received_parts,
        missing_parts=missing_parts,
        trip_id=ingestion.trip_id,
        error=ingestion.error_message or None,
        progress=progress,
    )
