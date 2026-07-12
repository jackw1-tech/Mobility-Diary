from __future__ import annotations

from django.conf import settings
from django.db import transaction
from django.shortcuts import get_object_or_404
from django.utils import timezone
from ninja import Router
from ninja.errors import HttpError
from ninja.responses import Status

from accounts.auth_mobile.auth import mobile_bearer_auth

from ..models import (
    Trip,
    TripIngestion,
    TripIngestionPart,
)
from . import storage
from .selectors import (
    active_ingestions_for_owner,
)
from .services import (
    IngestionServiceError,
    abandon_recording,
    heartbeat_recording,
    process_inline_core_ingestion,
    queue_final_har,
    start_recording,
)
from .schemas import (
    ActiveIngestionConflictOut,
    ActiveIngestionOut,
    CompleteIn,
    CompleteOut,
    InlineCoreIn,
    InlineCoreOut,
    IngestionAbandonIn,
    IngestionAbandonOut,
    IngestionHeartbeatIn,
    IngestionHeartbeatOut,
    IngestionStartIn,
    IngestionStartOut,
    IngestionStatusOut,
    PartConfirmIn,
    PartConfirmOut,
    PartPresignIn,
    PartPresignOut,
)

router = Router(tags=["ingestion"])


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


def _missing_raw_parts(ingestion: TripIngestion) -> list[dict[str, int]]:
    confirmed = _confirmed_raw_sequences(ingestion)
    expected = _expected_part_sequences(ingestion.expected_raw_parts)
    return [
        {"sequence": seq}
        for seq in expected
        if seq not in confirmed
    ]


def _mark_raw_received_if_complete(ingestion: TripIngestion) -> None:
    expected = _expected_part_sequences(ingestion.expected_raw_parts)
    if not expected:
        return
    confirmed = _confirmed_raw_sequences(ingestion)
    if all(sequence in confirmed for sequence in expected):
        if ingestion.raw_status == TripIngestion.PhaseStatus.RECEIVING:
            ingestion.raw_status = TripIngestion.PhaseStatus.RECEIVED
            ingestion.save(update_fields=["raw_status", "updated_at"])


def _get_owned_ingestion(request, ingestion_id: int) -> TripIngestion:
    return get_object_or_404(
        TripIngestion,
        id=ingestion_id,
        user_id=request.auth.user_id,
    )


def _validate_expected_parts(count: int) -> int:
    normalized_count = int(count or 0)
    if normalized_count < 0:
        raise HttpError(422, "expected_raw_parts contiene count non valido")
    return normalized_count


def _ensure_part_was_declared(
    ingestion: TripIngestion,
    sequence: int,
) -> None:
    expected_count = _raw_part_count(ingestion.expected_raw_parts)
    if sequence < 1 or sequence > expected_count:
        raise HttpError(
            409,
            f"parte non dichiarata nel manifest iniziale: #{sequence}",
        )


def _active_response(ingestion: TripIngestion) -> ActiveIngestionOut:
    return ActiveIngestionOut(
        ingestion_id=ingestion.id,
        client_session_id=ingestion.client_session_id,
        device_id=ingestion.device_id,
        recording_started_at=ingestion.recording_started_at,
        last_seen_at=ingestion.last_seen_at,
    )


@router.get(
    "/trips/active",
    response={200: ActiveIngestionOut, 404: dict},
    auth=mobile_bearer_auth,
)
def get_active_ingestion(request):
    active = active_ingestions_for_owner(request.auth.user_id).first()
    if active is None:
        return Status(404, {"detail": "nessun viaggio in corso"})
    return _active_response(active)


@router.post(
    "/trips/{ingestion_id}/abandon",
    response=IngestionAbandonOut,
    auth=mobile_bearer_auth,
)
def abandon_ingestion(request, ingestion_id: int, payload: IngestionAbandonIn):
    try:
        ingestion = abandon_recording(
            user_id=request.auth.user_id,
            ingestion_id=ingestion_id,
            device_id=payload.device_id,
        )
    except IngestionServiceError as exc:
        raise HttpError(exc.status_code, exc.message) from exc

    return IngestionAbandonOut(
        ingestion_id=ingestion.id,
        recording_abandoned_at=ingestion.recording_abandoned_at,
    )


@router.post(
    "/trips/{ingestion_id}/heartbeat",
    response=IngestionHeartbeatOut,
    auth=mobile_bearer_auth,
)
def heartbeat_ingestion(request, ingestion_id: int, payload: IngestionHeartbeatIn):
    try:
        ingestion = heartbeat_recording(
            user_id=request.auth.user_id,
            ingestion_id=ingestion_id,
            client_session_id=payload.client_session_id,
            device_id=payload.device_id,
        )
    except IngestionServiceError as exc:
        raise HttpError(exc.status_code, exc.message) from exc

    return IngestionHeartbeatOut(
        ingestion_id=ingestion.id,
        last_seen_at=ingestion.last_seen_at,
    )


@router.post(
    "/trips/start",
    response={200: IngestionStartOut, 409: ActiveIngestionConflictOut},
    auth=mobile_bearer_auth,
)
def start_ingestion(request, payload: IngestionStartIn):
    try:
        result = start_recording(
            user_id=request.auth.user_id,
            client_session_id=payload.client_session_id,
            device_id=payload.device_id,
            started_at=payload.started_at,
            source_trip_id=payload.source_trip_id,
        )
    except IngestionServiceError as exc:
        raise HttpError(exc.status_code, exc.message) from exc

    if result.conflict_ingestion is not None:
        return Status(
            409,
            ActiveIngestionConflictOut(
                detail="viaggio in corso gia' presente",
                active_ingestion=_active_response(result.conflict_ingestion),
            ),
        )
    return IngestionStartOut(
        ingestion_id=result.ingestion.id,
        client_session_id=result.ingestion.client_session_id,
        device_id=result.ingestion.device_id,
        recording_started_at=result.ingestion.recording_started_at,
        already_exists=result.already_exists,
    )


@router.post(
    "/trips/core",
    response={200: InlineCoreOut, 409: dict, 410: dict},
    auth=mobile_bearer_auth,
)
def create_core_inline(request, payload: InlineCoreIn):
    body_size = len(request.body or b"")
    if not payload.gps_points and not payload.state_transitions:
        raise HttpError(400, "core vuoto: GPS e state transitions assenti")

    expected_raw_parts = _validate_expected_parts(payload.expected_raw_parts)

    if expected_raw_parts:
        raw_status = TripIngestion.PhaseStatus.PENDING
    else:
        raw_status = TripIngestion.PhaseStatus.COMPLETED

    try:
        ingestion = process_inline_core_ingestion(
            user_id=request.auth.user_id,
            payload=payload,
            expected_raw_parts=expected_raw_parts,
            raw_status=raw_status,
            body_size=body_size,
        )
    except IngestionServiceError as exc:
        raise HttpError(exc.status_code, exc.message) from exc

    return InlineCoreOut(
        ingestion_id=ingestion.id,
        trip_id=ingestion.trip_id,
        core_status=ingestion.core_status,
        raw_status=ingestion.raw_status,
        map_available=bool(ingestion.trip_id and ingestion.trip.path),
    )


@router.post(
    "/trips/{ingestion_id}/parts/presign",
    response=PartPresignOut,
    auth=mobile_bearer_auth,
)
def presign_part(request, ingestion_id: int, payload: PartPresignIn):
    if payload.size_bytes <= 0 or payload.size_bytes > settings.INGESTION_MAX_PART_BYTES:
        raise HttpError(
            422,
            f"size_bytes fuori range (max {settings.INGESTION_MAX_PART_BYTES})",
        )

    ingestion = _get_owned_ingestion(request, ingestion_id)
    _ensure_part_was_declared(ingestion, payload.sequence)

    object_key = _object_key(ingestion.raw_base_path, payload.sequence)

    with transaction.atomic():
        part, _ = TripIngestionPart.objects.select_for_update().get_or_create(
            ingestion=ingestion,
            sequence=payload.sequence,
            defaults={
                "sha256": payload.sha256,
                "size_bytes": payload.size_bytes,
                "object_key": object_key,
            },
        )
        if ingestion.raw_status == TripIngestion.PhaseStatus.PENDING:
            ingestion.raw_status = TripIngestion.PhaseStatus.RECEIVING
            ingestion.save(update_fields=["raw_status", "updated_at"])

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
    ingestion = _get_owned_ingestion(request, ingestion_id)
    part = get_object_or_404(
        TripIngestionPart,
        ingestion=ingestion,
        sequence=payload.sequence,
    )

    if part.sha256 != payload.sha256:
        raise HttpError(
            409,
            "checksum non corrisponde a quello dichiarato in presign",
        )

    head = storage.head_object(part.object_key)
    if head is None:
        raise HttpError(409, "oggetto non presente sullo storage")
    metadata_sha256 = (head.get("Metadata") or {}).get("sha256")
    if metadata_sha256 != part.sha256:
        raise HttpError(409, "sha256 metadata non corrisponde")

    part.received_at = timezone.now()
    part.save(update_fields=["received_at"])
    _mark_raw_received_if_complete(ingestion)
    return PartConfirmOut(
        ingestion_id=ingestion.id,
        sequence=part.sequence,
        status="RECEIVED",
    )


@router.post(
    "/trips/{ingestion_id}/complete-raw",
    response={202: CompleteOut},
    auth=mobile_bearer_auth,
)
def complete_raw_ingestion(request, ingestion_id: int, payload: CompleteIn):
    ingestion = _get_owned_ingestion(request, ingestion_id)

    with transaction.atomic():
        ingestion = (
            TripIngestion.objects.select_for_update()
            .get(id=ingestion.id)
        )
        if ingestion.raw_status == TripIngestion.PhaseStatus.FAILED_FINAL:
            raise HttpError(409, "raw sensor ingestion fallita definitivamente")
        if (
            payload.total_parts is not None
            and payload.total_parts != _raw_part_count(ingestion.expected_raw_parts)
        ):
            raise HttpError(409, "numero parti raw diverso dal manifest iniziale")

        try:
            queue_final_har(ingestion, now=timezone.now())
        except IngestionServiceError as exc:
            raise HttpError(exc.status_code, exc.message) from exc
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

    return IngestionStatusOut(
        ingestion_id=ingestion.id,
        core_status=ingestion.core_status,
        raw_status=ingestion.raw_status,
        missing_raw_parts=_missing_raw_parts(ingestion),
        trip_id=ingestion.trip_id,
        map_available=bool(ingestion.trip_id and ingestion.trip.path),
    )
