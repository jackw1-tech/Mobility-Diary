"""API di ingestione asincrona dei viaggi.

Upload "stupido" e affidabile: il backend non riceve mai i byte pesanti, genera
presigned URL e tiene la contabilita' delle parti. Il processing (materializzazione
Trip + HAR) e' demandato a Celery (REPORT_STRATEGIA_INGESTION_ASINCRONA.md).

Flusso: create -> presign/PUT/confirm core -> complete-core ->
presign/PUT/confirm raw -> complete-raw.
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

_CORE_KINDS = {PartKind.GPS_POINTS, PartKind.STATE_TRANSITIONS}
_RAW_KINDS = {PartKind.SENSOR_WINDOWS}
_VALID_KINDS = _CORE_KINDS | _RAW_KINDS
_RECEIVING_STATES = {
    TripIngestion.PhaseStatus.PENDING,
    TripIngestion.PhaseStatus.RECEIVING,
    TripIngestion.PhaseStatus.RECEIVED,
}


def _object_key(base_path: str, kind: str, sequence: int) -> str:
    if kind == PartKind.SENSOR_WINDOWS:
        return f"{base_path}sensor_windows_part_{sequence:04d}.json.gz"
    return f"{base_path}{kind}.json.gz"


def _expected_part_keys(parts: dict[str, int]) -> list[tuple[str, int]]:
    expected: list[tuple[str, int]] = []
    for kind, count in (parts or {}).items():
        for sequence in range(1, int(count) + 1):
            expected.append((kind, sequence))
    return expected


def _part_phase(kind: str) -> str:
    if kind in _CORE_KINDS:
        return "core"
    if kind in _RAW_KINDS:
        return "raw"
    raise HttpError(422, f"kind non valido: {kind}")


def _phase_status(ingestion: TripIngestion, phase: str) -> str:
    return ingestion.core_status if phase == "core" else ingestion.raw_status


def _set_phase_status(ingestion: TripIngestion, phase: str, status: str) -> None:
    if phase == "core":
        ingestion.core_status = status
    else:
        ingestion.raw_status = status


def _expected_parts_for_phase(ingestion: TripIngestion, phase: str) -> dict[str, int]:
    return ingestion.expected_core_parts if phase == "core" else ingestion.expected_raw_parts


def _confirmed_parts(ingestion: TripIngestion) -> set[tuple[str, int]]:
    return {
        (kind, seq)
        for kind, seq in ingestion.parts.filter(received_at__isnull=False).values_list(
            "kind", "sequence"
        )
    }


def _phase_part_state(
    ingestion: TripIngestion,
    phase: str,
) -> tuple[list[dict[str, int | str]], list[dict[str, int | str]], int]:
    confirmed = _confirmed_parts(ingestion)
    expected = _expected_part_keys(_expected_parts_for_phase(ingestion, phase))
    received_parts = [
        {"kind": kind, "sequence": seq}
        for kind, seq in expected
        if (kind, seq) in confirmed
    ]
    missing_parts = [
        {"kind": kind, "sequence": seq}
        for kind, seq in expected
        if (kind, seq) not in confirmed
    ]
    progress = round(100 * len(received_parts) / len(expected)) if expected else 100
    return received_parts, missing_parts, progress


def _mark_phase_received_if_complete(ingestion: TripIngestion, phase: str) -> None:
    expected = _expected_part_keys(_expected_parts_for_phase(ingestion, phase))
    if not expected:
        return
    confirmed = _confirmed_parts(ingestion)
    if all(part_key in confirmed for part_key in expected):
        current = _phase_status(ingestion, phase)
        if current == TripIngestion.PhaseStatus.RECEIVING:
            _set_phase_status(ingestion, phase, TripIngestion.PhaseStatus.RECEIVED)
            ingestion.save(
                update_fields=[
                    "core_status" if phase == "core" else "raw_status",
                    "updated_at",
                ]
            )


def _get_owned_ingestion(request, ingestion_id: int) -> TripIngestion:
    return get_object_or_404(
        TripIngestion, id=ingestion_id, user_id=request.auth.user_id
    )


def _validate_kind(kind: str) -> None:
    if kind not in _VALID_KINDS:
        raise HttpError(422, f"kind non valido: {kind}")


def _validate_expected_parts(
    parts: dict[str, int],
    allowed_kinds: set[str],
    label: str,
) -> dict[str, int]:
    normalized: dict[str, int] = {}
    for kind, count in (parts or {}).items():
        if kind not in allowed_kinds:
            raise HttpError(422, f"expected_{label}_parts contiene kind non valido: {kind}")
        if count <= 0:
            raise HttpError(422, f"expected_{label}_parts contiene count non valido: {kind}")
        normalized[kind] = int(count)
    return normalized


def _ensure_part_was_declared(
    ingestion: TripIngestion,
    phase: str,
    kind: str,
    sequence: int,
) -> None:
    expected_count = int(_expected_parts_for_phase(ingestion, phase).get(kind, 0) or 0)
    if sequence < 1 or sequence > expected_count:
        raise HttpError(409, f"parte non dichiarata nel manifest iniziale: {kind}#{sequence}")


@router.post("/trips", response=IngestionCreateOut, auth=mobile_bearer_auth)
def create_ingestion(request, payload: IngestionCreateIn):
    user_id = request.auth.user_id
    expected_core_parts = _validate_expected_parts(
        payload.expected_core_parts,
        _CORE_KINDS,
        "core",
    )
    expected_raw_parts = _validate_expected_parts(
        payload.expected_raw_parts,
        _RAW_KINDS,
        "raw",
    )
    raw_status = (
        TripIngestion.PhaseStatus.PENDING
        if expected_raw_parts
        else TripIngestion.PhaseStatus.COMPLETED
    )
    ingestion, created = TripIngestion.objects.get_or_create(
        user_id=user_id,
        client_session_id=payload.client_session_id,
        defaults={
            "device_id": payload.device_id,
            "schema_version": payload.schema_version,
            "expected_core_parts": expected_core_parts,
            "expected_raw_parts": expected_raw_parts,
            "raw_status": raw_status,
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
        core_status=ingestion.core_status,
        raw_status=ingestion.raw_status,
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
    phase = _part_phase(payload.kind)
    phase_status = _phase_status(ingestion, phase)
    _ensure_part_was_declared(ingestion, phase, payload.kind, payload.sequence)
    if phase_status not in _RECEIVING_STATES:
        raise HttpError(
            409,
            f"ingestion {phase} in stato {phase_status}, upload non ammesso",
        )

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

        if phase_status == TripIngestion.PhaseStatus.PENDING:
            _set_phase_status(ingestion, phase, TripIngestion.PhaseStatus.RECEIVING)
            ingestion.save(
                update_fields=[
                    "core_status" if phase == "core" else "raw_status",
                    "updated_at",
                ]
            )

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
    _mark_phase_received_if_complete(ingestion, _part_phase(part.kind))
    return PartConfirmOut(
        ingestion_id=ingestion.id,
        kind=part.kind,
        sequence=part.sequence,
        status="RECEIVED",
    )


@router.post(
    "/trips/{ingestion_id}/complete-core",
    response={202: CompleteOut},
    auth=mobile_bearer_auth,
)
def complete_core_ingestion(request, ingestion_id: int, payload: CompleteIn):
    ingestion = _get_owned_ingestion(request, ingestion_id)

    # Idempotente: se gia' in coda o oltre, non rifare nulla.
    if ingestion.core_status in {
        TripIngestion.PhaseStatus.QUEUED,
        TripIngestion.PhaseStatus.PROCESSING,
        TripIngestion.PhaseStatus.COMPLETED,
        TripIngestion.PhaseStatus.FAILED_RETRYABLE,
    }:
        return 202, CompleteOut(
            ingestion_id=ingestion.id,
            core_status=ingestion.core_status,
            raw_status=ingestion.raw_status,
        )
    if ingestion.core_status == TripIngestion.PhaseStatus.FAILED_FINAL:
        raise HttpError(409, "core ingestion fallita definitivamente")

    expected = _expected_part_keys(ingestion.expected_core_parts)
    if not expected:
        raise HttpError(409, "nessuna parte core attesa")
    confirmed = _confirmed_parts(ingestion)
    missing = [pk for pk in expected if pk not in confirmed]
    if missing:
        readable = ", ".join(f"{kind}#{seq}" for kind, seq in missing)
        raise HttpError(409, f"parti core mancanti: {readable}")

    with transaction.atomic():
        ingestion.manifest_sha256 = payload.manifest_sha256
        ingestion.core_status = TripIngestion.PhaseStatus.QUEUED
        ingestion.queued_at = timezone.now()
        ingestion.save(
            update_fields=["manifest_sha256", "core_status", "queued_at", "updated_at"]
        )

    # Import locale: evita import circolare e accoppiamento a Celery a load-time.
    from ..tasks import process_trip_ingestion

    transaction.on_commit(lambda: process_trip_ingestion.delay(ingestion.id))
    return 202, CompleteOut(
        ingestion_id=ingestion.id,
        core_status=ingestion.core_status,
        raw_status=ingestion.raw_status,
    )


@router.post(
    "/trips/{ingestion_id}/complete-raw",
    response={202: CompleteOut},
    auth=mobile_bearer_auth,
)
def complete_raw_ingestion(request, ingestion_id: int, payload: CompleteIn):
    ingestion = _get_owned_ingestion(request, ingestion_id)

    if ingestion.core_status != TripIngestion.PhaseStatus.COMPLETED:
        raise HttpError(409, "core ingestion non ancora completata")

    if ingestion.raw_status in {
        TripIngestion.PhaseStatus.RECEIVED,
        TripIngestion.PhaseStatus.COMPLETED,
        TripIngestion.PhaseStatus.FAILED_RETRYABLE,
    }:
        return 202, CompleteOut(
            ingestion_id=ingestion.id,
            core_status=ingestion.core_status,
            raw_status=ingestion.raw_status,
        )
    if ingestion.raw_status == TripIngestion.PhaseStatus.FAILED_FINAL:
        raise HttpError(409, "raw sensor ingestion fallita definitivamente")

    expected = _expected_part_keys(ingestion.expected_raw_parts)
    if not expected:
        ingestion.raw_status = TripIngestion.PhaseStatus.COMPLETED
        ingestion.save(update_fields=["raw_status", "updated_at"])
        return 202, CompleteOut(
            ingestion_id=ingestion.id,
            core_status=ingestion.core_status,
            raw_status=ingestion.raw_status,
        )

    confirmed = _confirmed_parts(ingestion)
    missing = [pk for pk in expected if pk not in confirmed]
    if missing:
        readable = ", ".join(f"{kind}#{seq}" for kind, seq in missing)
        raise HttpError(409, f"parti raw mancanti: {readable}")

    ingestion.raw_status = TripIngestion.PhaseStatus.RECEIVED
    ingestion.save(update_fields=["raw_status", "updated_at"])

    # HAR finale e' predisposto ma non attivo: per ora la raw phase si ferma a RECEIVED.
    return 202, CompleteOut(
        ingestion_id=ingestion.id,
        core_status=ingestion.core_status,
        raw_status=ingestion.raw_status,
    )


@router.get(
    "/trips/{ingestion_id}", response=IngestionStatusOut, auth=mobile_bearer_auth
)
def ingestion_status(request, ingestion_id: int):
    ingestion = _get_owned_ingestion(request, ingestion_id)

    received_core_parts, missing_core_parts, core_progress = _phase_part_state(
        ingestion, "core"
    )
    received_raw_parts, missing_raw_parts, raw_progress = _phase_part_state(
        ingestion, "raw"
    )

    return IngestionStatusOut(
        ingestion_id=ingestion.id,
        core_status=ingestion.core_status,
        raw_status=ingestion.raw_status,
        received_core_parts=received_core_parts,
        missing_core_parts=missing_core_parts,
        received_raw_parts=received_raw_parts,
        missing_raw_parts=missing_raw_parts,
        trip_id=ingestion.trip_id,
        error=ingestion.error_message or None,
        core_progress=core_progress,
        raw_progress=raw_progress,
    )
