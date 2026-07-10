"""API di ingestione asincrona dei viaggi.

Upload "stupido" e affidabile: il backend riceve il core inline e non riceve
i byte pesanti delle sensor window raw, per cui genera presigned URL e tiene
la contabilita' delle parti raw. Il processing HAR e' demandato a Celery.

Flusso: core inline -> presign/PUT/confirm raw -> complete-raw.
"""
from __future__ import annotations

import hashlib
import json

from django.conf import settings
from django.db import transaction
from django.shortcuts import get_object_or_404
from django.utils import timezone
from ninja import Router
from ninja.errors import HttpError
from ninja.responses import Status

from accounts.auth_mobile.auth import mobile_bearer_auth

from ..models import (
    PartKind,
    Trip,
    TripIngestion,
    TripIngestionPart,
)
from . import storage
from .materialization import (
    materialized_trip_counts,
)
from .selectors import (
    first_active_ingestion_for_owner,
    owned_ingestions_for_owner,
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

_RAW_KINDS = {PartKind.SENSOR_WINDOWS}
_VALID_KINDS = _RAW_KINDS
_RECEIVING_STATES = {
    TripIngestion.PhaseStatus.PENDING,
    TripIngestion.PhaseStatus.RECEIVING,
    TripIngestion.PhaseStatus.RECEIVED,
}


def _object_key(base_path: str, kind: str, sequence: int) -> str:
    return f"{base_path}sensor_windows_part_{sequence:04d}.bin.gz"


def _expected_part_keys(parts: dict[str, int]) -> list[tuple[str, int]]:
    expected: list[tuple[str, int]] = []
    for kind, count in (parts or {}).items():
        for sequence in range(1, int(count) + 1):
            expected.append((kind, sequence))
    return expected


def _part_phase(kind: str) -> str:
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
        owned_ingestions_for_owner(request.auth.user_id),
        id=ingestion_id,
    )


def _map_available(ingestion: TripIngestion) -> bool:
    trip = ingestion.trip
    return bool(trip is not None and trip.path is not None)


def _canonical_inline_payload(payload: InlineCoreIn) -> dict:
    # Manteniamo i campi null (accuracy_meters, sigma, speed_mps, started/ended_at):
    # il client li include nel suo hash canonico. Rimuoviamo solo i campi opzionali
    # che il client omette del tutto quando assenti (``ingestion_id`` per i client
    # legacy, ``cutoff_source_timestamp`` per i viaggi non-replay), cosi' l'hash
    # combacia.
    data = payload.model_dump(mode="json")
    data.pop("core_payload_sha256", None)
    for optional_field in ("ingestion_id", "cutoff_source_timestamp"):
        if data.get(optional_field) is None:
            data.pop(optional_field, None)
    return data


def _stable_json_bytes(data: dict) -> bytes:
    return json.dumps(
        data,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode("utf-8")


def _inline_payload_sha256(payload: InlineCoreIn) -> str:
    return hashlib.sha256(
        _stable_json_bytes(_canonical_inline_payload(payload))
    ).hexdigest()


def _materialized_counts(trip: Trip | None) -> tuple[int, int, int, float]:
    counts = materialized_trip_counts(trip)
    return (
        counts.gps_points,
        counts.state_transitions,
        counts.path_points,
        counts.distance_meters,
    )


def _inline_core_response(ingestion: TripIngestion) -> InlineCoreOut:
    if (
        ingestion.core_status == TripIngestion.PhaseStatus.COMPLETED
        and ingestion.trip_id is None
    ):
        raise HttpError(409, "core completato senza trip materializzato")
    gps_count, transition_count, path_points, distance_meters = _materialized_counts(
        ingestion.trip
    )
    return InlineCoreOut(
        ingestion_id=ingestion.id,
        trip_id=ingestion.trip_id,
        core_status=ingestion.core_status,
        raw_status=ingestion.raw_status,
        gps_points=gps_count,
        state_transitions=transition_count,
        path_points=path_points,
        distance_meters=distance_meters,
        map_available=_map_available(ingestion),
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


def _start_response(
    ingestion: TripIngestion,
    *,
    already_exists: bool,
) -> IngestionStartOut:
    return IngestionStartOut(
        ingestion_id=ingestion.id,
        client_session_id=ingestion.client_session_id,
        device_id=ingestion.device_id,
        recording_started_at=ingestion.recording_started_at,
        already_exists=already_exists,
    )


def _active_response(ingestion: TripIngestion) -> ActiveIngestionOut:
    return ActiveIngestionOut(
        ingestion_id=ingestion.id,
        client_session_id=ingestion.client_session_id,
        device_id=ingestion.device_id,
        recording_started_at=ingestion.recording_started_at,
        last_seen_at=ingestion.last_seen_at,
    )


def _active_conflict_response(
    ingestion: TripIngestion,
) -> ActiveIngestionConflictOut:
    return ActiveIngestionConflictOut(
        detail="viaggio in corso gia' presente",
        active_ingestion=_active_response(ingestion),
    )


def _raise_ingestion_service_error(exc: IngestionServiceError) -> None:
    raise HttpError(exc.status_code, exc.message) from exc


@router.get(
    "/trips/active",
    response={200: ActiveIngestionOut, 404: dict},
    auth=mobile_bearer_auth,
)
def get_active_ingestion(request):
    active = first_active_ingestion_for_owner(request.auth.user_id)
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
        _raise_ingestion_service_error(exc)

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
        _raise_ingestion_service_error(exc)

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
            schema_version=payload.schema_version,
            timezone_name=payload.timezone,
            app_version=payload.app_version,
            device_platform=payload.device_platform,
            started_at=payload.started_at,
            source_trip_id=payload.source_trip_id,
        )
    except IngestionServiceError as exc:
        _raise_ingestion_service_error(exc)

    if result.conflict_ingestion is not None:
        return Status(409, _active_conflict_response(result.conflict_ingestion))
    return _start_response(result.ingestion, already_exists=result.already_exists)


@router.post(
    "/trips/core",
    response={200: InlineCoreOut, 409: dict, 410: dict},
    auth=mobile_bearer_auth,
)
def create_core_inline(request, payload: InlineCoreIn):
    body_size = len(request.body or b"")
    if not payload.gps_points and not payload.state_transitions:
        raise HttpError(400, "core vuoto: GPS e state transitions assenti")

    expected_raw_parts = _validate_expected_parts(
        payload.expected_raw_parts,
        _RAW_KINDS,
        "raw",
    )
    actual_sha256 = _inline_payload_sha256(payload)
    if payload.core_payload_sha256 != actual_sha256:
        raise HttpError(400, "core_payload_sha256 non corrisponde al payload")

    raw_status = (
        TripIngestion.PhaseStatus.PENDING
        if expected_raw_parts
        else TripIngestion.PhaseStatus.COMPLETED
    )

    try:
        ingestion = process_inline_core_ingestion(
            user_id=request.auth.user_id,
            payload=payload,
            expected_raw_parts=expected_raw_parts,
            raw_status=raw_status,
            actual_sha256=actual_sha256,
            body_size=body_size,
        )
    except IngestionServiceError as exc:
        _raise_ingestion_service_error(exc)

    return _inline_core_response(ingestion)

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
        if ingestion.core_status != TripIngestion.PhaseStatus.COMPLETED:
            raise HttpError(409, "core ingestion non ancora completata")

        if ingestion.raw_status in {
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
        if ingestion.raw_status == TripIngestion.PhaseStatus.FAILED_FINAL:
            raise HttpError(409, "raw sensor ingestion fallita definitivamente")

        expected = _expected_part_keys(ingestion.expected_raw_parts)
        if not expected:
            try:
                queue_final_har(ingestion, now=timezone.now())
            except IngestionServiceError as exc:
                _raise_ingestion_service_error(exc)
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

        if ingestion.trip_id is None:
            raise HttpError(409, "trip non materializzato per HAR finale")
        ingestion.manifest_sha256 = payload.manifest_sha256
        ingestion.save(update_fields=["manifest_sha256", "updated_at"])
        try:
            queue_final_har(ingestion, now=timezone.now())
        except IngestionServiceError as exc:
            _raise_ingestion_service_error(exc)
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
        core_ingestion_mode=ingestion.core_ingestion_mode,
        received_core_parts=received_core_parts,
        missing_core_parts=missing_core_parts,
        received_raw_parts=received_raw_parts,
        missing_raw_parts=missing_raw_parts,
        trip_id=ingestion.trip_id,
        map_available=_map_available(ingestion),
        error=ingestion.error_message or None,
        core_progress=core_progress,
        raw_progress=raw_progress,
    )
