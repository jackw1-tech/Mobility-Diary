from __future__ import annotations

from django.shortcuts import get_object_or_404
from ninja import Router
from ninja.errors import HttpError
from ninja.responses import Status

from accounts.auth_mobile.auth import mobile_bearer_auth

from ..models import TripUpload
from .services import (
    UploadServiceError,
    active_recording_for_user,
    abandon_recording,
    complete_raw_upload,
    confirm_raw_part,
    heartbeat_recording,
    missing_raw_parts,
    presign_raw_part,
    process_inline_core_upload,
    start_recording,
    validate_expected_parts,
)
from .schemas import (
    ActiveUploadConflictOut,
    ActiveUploadOut,
    CompleteIn,
    CompleteOut,
    InlineCoreIn,
    InlineCoreOut,
    UploadAbandonIn,
    UploadAbandonOut,
    UploadHeartbeatIn,
    UploadHeartbeatOut,
    UploadStartIn,
    UploadStartOut,
    UploadStatusOut,
    PartConfirmIn,
    PartConfirmOut,
    PartPresignIn,
    PartPresignOut,
)

router = Router(tags=["upload"])


def _active_response(upload: TripUpload) -> ActiveUploadOut:
    return ActiveUploadOut(
        upload_id=upload.id,
        client_session_id=upload.client_session_id,
        device_id=upload.device_id,
        recording_started_at=upload.recording_started_at,
        last_seen_at=upload.last_seen_at,
    )


@router.get(
    "/trips/active",
    response={200: ActiveUploadOut, 404: dict},
    auth=mobile_bearer_auth,
)
def get_active_upload(request):
    active = active_recording_for_user(request.user.user_id)
    if active is None:
        return Status(404, {"detail": "nessun viaggio in corso"})
    return _active_response(active)


@router.post(
    "/trips/{upload_id}/abandon",
    response=UploadAbandonOut,
    auth=mobile_bearer_auth,
)
def abandon_upload(request, upload_id: int, payload: UploadAbandonIn):
    try:
        upload = abandon_recording(
            user_id=request.user.user_id,
            upload_id=upload_id,
            device_id=payload.device_id,
        )
    except UploadServiceError as exc:
        raise HttpError(exc.status_code, exc.message) from exc

    return UploadAbandonOut(
        upload_id=upload.id,
        recording_abandoned_at=upload.recording_abandoned_at,
    )


@router.post(
    "/trips/{upload_id}/heartbeat",
    response=UploadHeartbeatOut,
    auth=mobile_bearer_auth,
)
def heartbeat_upload(request, upload_id: int, payload: UploadHeartbeatIn):
    try:
        upload = heartbeat_recording(
            user_id=request.user.user_id,
            upload_id=upload_id,
            client_session_id=payload.client_session_id,
            device_id=payload.device_id,
        )
    except UploadServiceError as exc:
        raise HttpError(exc.status_code, exc.message) from exc

    return UploadHeartbeatOut(
        upload_id=upload.id,
        last_seen_at=upload.last_seen_at,
    )


@router.post(
    "/trips/start",
    response={200: UploadStartOut, 409: ActiveUploadConflictOut},
    auth=mobile_bearer_auth,
)
def start_upload(request, payload: UploadStartIn):
    try:
        result = start_recording(
            user_id=request.user.user_id,
            client_session_id=payload.client_session_id,
            device_id=payload.device_id,
            started_at=payload.started_at,
            source_trip_id=payload.source_trip_id,
        )
    except UploadServiceError as exc:
        raise HttpError(exc.status_code, exc.message) from exc

    if result.conflict_upload is not None:
        return Status(
            409,
            ActiveUploadConflictOut(
                detail="viaggio in corso gia' presente",
                active_upload=_active_response(result.conflict_upload),
            ),
        )
    return UploadStartOut(
        upload_id=result.upload.id,
        client_session_id=result.upload.client_session_id,
        device_id=result.upload.device_id,
        recording_started_at=result.upload.recording_started_at,
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
    except UploadServiceError as exc:
        raise HttpError(exc.status_code, exc.message) from exc

    if expected_raw_parts:
        raw_status = TripUpload.PhaseStatus.PENDING
    else:
        raw_status = TripUpload.PhaseStatus.COMPLETED

    try:
        upload = process_inline_core_upload(
            user_id=request.user.user_id,
            payload=payload,
            expected_raw_parts=expected_raw_parts,
            raw_status=raw_status,
            body_size=body_size,
        )
    except UploadServiceError as exc:
        raise HttpError(exc.status_code, exc.message) from exc

    return InlineCoreOut(
        upload_id=upload.id,
        trip_id=upload.trip_id,
        core_status=upload.core_status,
        raw_status=upload.raw_status,
        map_available=bool(upload.trip_id and upload.trip.path),
    )

## Rotta che genera l'url per il caricamento diretto di un singolo blocco 
@router.post(
    "/trips/{upload_id}/parts/presign",
    response=PartPresignOut,
    auth=mobile_bearer_auth,
)
def presign_part(request, upload_id: int, payload: PartPresignIn):
    try:
        result = presign_raw_part(
            user_id=request.user.user_id,
            upload_id=upload_id,
            sequence=payload.sequence,
            sha256=payload.sha256,
        )
    except UploadServiceError as exc:
        raise HttpError(exc.status_code, exc.message) from exc

    return PartPresignOut(
        object_key=result.object_key,
        upload_url=result.upload_url,
        upload_headers=result.upload_headers,
        expires_in=result.expires_in,
    )


@router.post(
    "/trips/{upload_id}/parts/confirm",
    response=PartConfirmOut,
    auth=mobile_bearer_auth,
)
def confirm_part(request, upload_id: int, payload: PartConfirmIn):
    try:
        part = confirm_raw_part(
            user_id=request.user.user_id,
            upload_id=upload_id,
            sequence=payload.sequence,
            sha256=payload.sha256,
        )
    except UploadServiceError as exc:
        raise HttpError(exc.status_code, exc.message) from exc

    return PartConfirmOut(
        upload_id=upload_id,
        sequence=part.sequence,
        status="RECEIVED",
    )


@router.post(
    "/trips/{upload_id}/complete-raw",
    response={202: CompleteOut},
    auth=mobile_bearer_auth,
)
def complete_raw_upload_route(request, upload_id: int, payload: CompleteIn):
    try:
        upload = complete_raw_upload(
            user_id=request.user.user_id,
            upload_id=upload_id,
            total_parts=payload.total_parts,
        )
    except UploadServiceError as exc:
        raise HttpError(exc.status_code, exc.message) from exc

    return 202, CompleteOut(
        upload_id=upload.id,
        core_status=upload.core_status,
        raw_status=upload.raw_status,
    )


@router.get(
    "/trips/{upload_id}", response=UploadStatusOut, auth=mobile_bearer_auth
)
def upload_status(request, upload_id: int):
    upload = get_object_or_404(
        TripUpload,
        id=upload_id,
        user_id=request.user.user_id,
    )

    return UploadStatusOut(
        upload_id=upload.id,
        core_status=upload.core_status,
        raw_status=upload.raw_status,
        missing_raw_parts=missing_raw_parts(upload),
        trip_id=upload.trip_id,
        map_available=bool(upload.trip_id and upload.trip.path),
    )
