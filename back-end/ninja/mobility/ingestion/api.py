from __future__ import annotations

from django.shortcuts import get_object_or_404
from ninja import Router
from ninja.errors import HttpError
from ninja.responses import Status

from accounts.auth_mobile.auth import mobile_bearer_auth

from ..models import TripIngestion
from .selectors import (
    active_ingestions_for_owner,
)
from .services import (
    IngestionServiceError,
    abandon_recording,
    complete_raw_ingestion,
    confirm_raw_part,
    heartbeat_recording,
    missing_raw_parts,
    presign_raw_part,
    process_inline_core_ingestion,
    start_recording,
    validate_expected_parts,
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

    try:
        expected_raw_parts = validate_expected_parts(payload.expected_raw_parts)
    except IngestionServiceError as exc:
        raise HttpError(exc.status_code, exc.message) from exc

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
    try:
        result = presign_raw_part(
            user_id=request.auth.user_id,
            ingestion_id=ingestion_id,
            sequence=payload.sequence,
            sha256=payload.sha256,
            size_bytes=payload.size_bytes,
        )
    except IngestionServiceError as exc:
        raise HttpError(exc.status_code, exc.message) from exc

    return PartPresignOut(
        object_key=result.object_key,
        upload_url=result.upload_url,
        upload_headers=result.upload_headers,
        expires_in=result.expires_in,
    )


@router.post(
    "/trips/{ingestion_id}/parts/confirm",
    response=PartConfirmOut,
    auth=mobile_bearer_auth,
)
def confirm_part(request, ingestion_id: int, payload: PartConfirmIn):
    try:
        part = confirm_raw_part(
            user_id=request.auth.user_id,
            ingestion_id=ingestion_id,
            sequence=payload.sequence,
            sha256=payload.sha256,
        )
    except IngestionServiceError as exc:
        raise HttpError(exc.status_code, exc.message) from exc

    return PartConfirmOut(
        ingestion_id=ingestion_id,
        sequence=part.sequence,
        status="RECEIVED",
    )


@router.post(
    "/trips/{ingestion_id}/complete-raw",
    response={202: CompleteOut},
    auth=mobile_bearer_auth,
)
def complete_raw_ingestion_route(request, ingestion_id: int, payload: CompleteIn):
    try:
        ingestion = complete_raw_ingestion(
            user_id=request.auth.user_id,
            ingestion_id=ingestion_id,
            total_parts=payload.total_parts,
        )
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
    ingestion = get_object_or_404(
        TripIngestion,
        id=ingestion_id,
        user_id=request.auth.user_id,
    )

    return IngestionStatusOut(
        ingestion_id=ingestion.id,
        core_status=ingestion.core_status,
        raw_status=ingestion.raw_status,
        missing_raw_parts=missing_raw_parts(ingestion),
        trip_id=ingestion.trip_id,
        map_available=bool(ingestion.trip_id and ingestion.trip.path),
    )
