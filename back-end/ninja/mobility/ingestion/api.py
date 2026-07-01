"""API di ingestione asincrona dei viaggi.

Upload "stupido" e affidabile: il backend non riceve mai i byte pesanti, genera
presigned URL e tiene la contabilita' delle parti. Il processing (materializzazione
Trip + HAR) e' demandato a Celery (REPORT_STRATEGIA_INGESTION_ASINCRONA.md).

Flusso: create -> presign/PUT/confirm core -> complete-core ->
presign/PUT/confirm raw -> complete-raw.
"""
from __future__ import annotations

import hashlib
import json
from datetime import datetime, timedelta

from django.conf import settings
from django.contrib.gis.geos import Point
from django.db import transaction
from django.db.models import Q
from django.shortcuts import get_object_or_404
from django.utils import timezone
from ninja import Router
from ninja.errors import HttpError
from ninja.responses import Status

from accounts.auth import mobile_bearer_auth

from ..models import (
    GpsPoint,
    HarJob,
    PartKind,
    StateTransition,
    Trip,
    TripIngestion,
    TripIngestionPart,
)
from . import storage
from ..replay_raw import regenerate_raw_and_queue_har
from .schemas import (
    ActiveIngestionConflictOut,
    ActiveIngestionOut,
    CompleteIn,
    CompleteOut,
    InlineCoreIn,
    InlineCoreOut,
    IngestionAbandonIn,
    IngestionAbandonOut,
    IngestionCreateIn,
    IngestionCreateOut,
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

_CORE_KINDS = {PartKind.GPS_POINTS, PartKind.STATE_TRANSITIONS}
_RAW_KINDS = {PartKind.SENSOR_WINDOWS}
_VALID_KINDS = _CORE_KINDS | _RAW_KINDS
_RECEIVING_STATES = {
    TripIngestion.PhaseStatus.PENDING,
    TripIngestion.PhaseStatus.RECEIVING,
    TripIngestion.PhaseStatus.RECEIVED,
}
_INLINE_REPROCESS_STATES = {
    TripIngestion.PhaseStatus.PENDING,
    TripIngestion.PhaseStatus.RECEIVING,
    TripIngestion.PhaseStatus.RECEIVED,
    TripIngestion.PhaseStatus.FAILED_RETRYABLE,
}
_INLINE_PASSIVE_STATES = {
    TripIngestion.PhaseStatus.QUEUED,
    TripIngestion.PhaseStatus.PROCESSING,
}
_ACTIVE_INGESTION_STALE_AFTER = timedelta(hours=24)


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
        TripIngestion.objects.select_related("trip"),
        id=ingestion_id,
        user_id=request.auth.user_id,
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
    if trip is None:
        return 0, 0, 0, 0
    gps_count = GpsPoint.objects.filter(trip=trip).count()
    transition_count = StateTransition.objects.filter(trip=trip).count()
    distance_meters = float(trip.distance_meters or 0)
    return gps_count, transition_count, gps_count, distance_meters


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


def _get_or_create_inline_trip(ingestion: TripIngestion) -> Trip:
    trip = (
        Trip.objects.select_for_update()
        .filter(client_session_id=ingestion.client_session_id)
        .first()
    )
    if trip is not None and trip.user_id not in {None, ingestion.user_id}:
        raise HttpError(409, "client_session_id gia' associato a un altro utente")
    ended_at = ingestion.ended_at or timezone.now()
    started_at = ingestion.started_at or ended_at
    if trip is None:
        return Trip.objects.create(
            user_id=ingestion.user_id,
            client_session_id=ingestion.client_session_id,
            device_id=ingestion.device_id or "unknown",
            status=Trip.Status.CLOSED,
            started_at=started_at,
            ended_at=ended_at,
        )

    update_fields = ["updated_at"]
    if trip.user_id is None:
        trip.user_id = ingestion.user_id
        update_fields.append("user")
    if not trip.device_id and ingestion.device_id:
        trip.device_id = ingestion.device_id
        update_fields.append("device_id")
    if trip.status == Trip.Status.OPEN:
        trip.status = Trip.Status.CLOSED
        update_fields.append("status")
    if trip.started_at is None:
        trip.started_at = started_at
        update_fields.append("started_at")
    if trip.ended_at is None:
        trip.ended_at = ended_at
        update_fields.append("ended_at")
    trip.save(update_fields=update_fields)
    return trip


def _materialize_inline_core(trip: Trip, payload: InlineCoreIn) -> tuple[int, int, int]:
    gps_rows = [
        GpsPoint(
            trip=trip,
            timestamp=point.timestamp,
            point=Point(point.longitude, point.latitude, srid=4326),
            speed_mps=point.speed_mps,
            accuracy_meters=point.accuracy_meters,
        )
        for point in payload.gps_points
    ]
    StateTransition.objects.bulk_create(
        [
            StateTransition(
                trip=trip,
                timestamp=transition.timestamp,
                from_state=transition.from_state,
                to_state=transition.to_state,
                reason=transition.reason,
                sigma=transition.sigma,
                speed_mps=transition.speed_mps,
            )
            for transition in payload.state_transitions
        ],
        ignore_conflicts=True,
    )
    GpsPoint.objects.bulk_create(gps_rows, ignore_conflicts=True)

    from ..tasks import _build_trip_path

    path_points = _build_trip_path(trip)
    gps_count = GpsPoint.objects.filter(trip=trip).count()
    transition_count = StateTransition.objects.filter(trip=trip).count()
    return gps_count, transition_count, path_points


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
        raise HttpError(409, "scegli uno slot nel passato")
    overlaps = (
        Trip.objects.filter(user_id=user_id, started_at__lt=ended_at)
        .filter(Q(ended_at__isnull=True) | Q(ended_at__gt=started_at))
        .exclude(client_session_id=client_session_id)
        .exists()
    )
    if overlaps:
        raise HttpError(409, "slot sovrapposto a un viaggio esistente")


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


def _active_ingestions(user_id: int):
    return TripIngestion.objects.filter(
        user_id=user_id,
        recording_started_at__isnull=False,
        recording_closed_at__isnull=True,
        recording_abandoned_at__isnull=True,
    )


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
    if now - _active_last_seen(ingestion) < _ACTIVE_INGESTION_STALE_AFTER:
        return False
    ingestion.recording_abandoned_at = now
    ingestion.save(update_fields=["recording_abandoned_at", "updated_at"])
    return True


def _release_active_lock_for_failed_final(
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


def _core_failed_final_status():
    return Status(409, {"detail": "core ingestion fallita definitivamente"})


def _get_inline_core_ingestion(
    request,
    payload: InlineCoreIn,
    *,
    expected_raw_parts: dict[str, int],
    raw_status: str,
    actual_sha256: str,
    body_size: int,
) -> TripIngestion:
    if payload.ingestion_id is None:
        ingestion, _ = TripIngestion.objects.select_for_update().get_or_create(
            user_id=request.auth.user_id,
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

    ingestion = (
        TripIngestion.objects.select_for_update()
        .filter(id=payload.ingestion_id, user_id=request.auth.user_id)
        .first()
    )
    if ingestion is None:
        raise HttpError(404, "ingestion non trovata")
    if ingestion.client_session_id != payload.client_session_id:
        raise HttpError(409, "client_session_id non corrisponde")
    if ingestion.device_id != payload.device_id:
        raise HttpError(403, "device_id non autorizzato")
    if ingestion.recording_started_at is None:
        raise HttpError(409, "viaggio non avviato")
    if ingestion.recording_abandoned_at is not None:
        raise HttpError(409, "viaggio abbandonato")
    if (
        ingestion.recording_closed_at is not None
        and ingestion.core_status != TripIngestion.PhaseStatus.COMPLETED
    ):
        raise HttpError(409, "viaggio gia' chiuso")
    return ingestion


@router.get(
    "/trips/active",
    response={200: ActiveIngestionOut, 404: dict},
    auth=mobile_bearer_auth,
)
def get_active_ingestion(request):
    active = _active_ingestions(request.auth.user_id).first()
    if active is None:
        return Status(404, {"detail": "nessun viaggio in corso"})
    return _active_response(active)


@router.post(
    "/trips/{ingestion_id}/abandon",
    response=IngestionAbandonOut,
    auth=mobile_bearer_auth,
)
def abandon_ingestion(request, ingestion_id: int, payload: IngestionAbandonIn):
    with transaction.atomic():
        ingestion = (
            TripIngestion.objects.select_for_update()
            .filter(id=ingestion_id, user_id=request.auth.user_id)
            .first()
        )
        if ingestion is None:
            raise HttpError(404, "ingestion non trovata")
        if ingestion.device_id != payload.device_id:
            raise HttpError(403, "solo il dispositivo origine puo' abbandonare")
        if ingestion.recording_closed_at is not None:
            raise HttpError(409, "viaggio gia' chiuso")
        if ingestion.recording_abandoned_at is None:
            ingestion.recording_abandoned_at = timezone.now()
            ingestion.save(update_fields=["recording_abandoned_at", "updated_at"])

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
    now = timezone.now()
    with transaction.atomic():
        ingestion = (
            TripIngestion.objects.select_for_update()
            .filter(id=ingestion_id, user_id=request.auth.user_id)
            .first()
        )
        if ingestion is None:
            raise HttpError(404, "ingestion non trovata")
        if ingestion.client_session_id != payload.client_session_id:
            raise HttpError(409, "client_session_id non corrisponde")
        if ingestion.device_id != payload.device_id:
            raise HttpError(403, "device_id non autorizzato")
        if (
            ingestion.recording_started_at is None
            or ingestion.recording_closed_at is not None
            or ingestion.recording_abandoned_at is not None
        ):
            raise HttpError(409, "viaggio non attivo")
        ingestion.last_seen_at = now
        ingestion.save(update_fields=["last_seen_at", "updated_at"])

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
    user_id = request.auth.user_id
    now = timezone.now()
    started_at = payload.started_at or now

    source_trip_id = None
    if payload.source_trip_id is not None:
        if not Trip.objects.filter(
            id=payload.source_trip_id,
            is_reloadable=True,
            status__in=[Trip.Status.CLOSED, Trip.Status.PROCESSED],
        ).exists():
            raise HttpError(409, "viaggio sorgente non ricaricabile")
        source_trip_id = payload.source_trip_id

    with transaction.atomic():
        active = _active_ingestions(user_id).select_for_update().first()
        if active is not None:
            if not _abandon_if_stale(active, now=now):
                if (
                    active.client_session_id == payload.client_session_id
                    and active.device_id == payload.device_id
                ):
                    return _start_response(active, already_exists=True)
                return Status(409, _active_conflict_response(active))

        ingestion = TripIngestion.objects.create(
            user_id=user_id,
            client_session_id=payload.client_session_id,
            device_id=payload.device_id,
            schema_version=payload.schema_version,
            timezone=payload.timezone,
            app_version=payload.app_version,
            device_platform=payload.device_platform,
            started_at=started_at,
            recording_started_at=started_at,
            last_seen_at=now,
            source_trip_id=source_trip_id,
        )
        if not ingestion.raw_base_path:
            ingestion.raw_base_path = f"ingestions/{ingestion.id}/"
            ingestion.save(update_fields=["raw_base_path", "updated_at"])

    return _start_response(ingestion, already_exists=False)


@router.post(
    "/trips/core",
    response={200: InlineCoreOut, 409: dict},
    auth=mobile_bearer_auth,
)
def create_core_inline(request, payload: InlineCoreIn):
    body_size = len(request.body or b"")
    if body_size > settings.INGESTION_INLINE_CORE_MAX_BYTES:
        raise HttpError(413, "payload core inline troppo grande")
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

    with transaction.atomic():
        ingestion = _get_inline_core_ingestion(
            request,
            payload,
            expected_raw_parts=expected_raw_parts,
            raw_status=raw_status,
            actual_sha256=actual_sha256,
            body_size=body_size,
        )
        if (
            ingestion.core_payload_sha256
            and ingestion.core_payload_sha256 != actual_sha256
        ):
            raise HttpError(409, "client_session_id gia' usato con core diverso")
        if not ingestion.raw_base_path:
            ingestion.raw_base_path = f"ingestions/{ingestion.id}/"
            ingestion.save(update_fields=["raw_base_path", "updated_at"])

        if ingestion.core_status == TripIngestion.PhaseStatus.FAILED_FINAL:
            _release_active_lock_for_failed_final(ingestion, now=timezone.now())
            return _core_failed_final_status()
        if ingestion.core_status == TripIngestion.PhaseStatus.COMPLETED:
            return _inline_core_response(ingestion)
        if ingestion.core_status in _INLINE_PASSIVE_STATES:
            return _inline_core_response(ingestion)
        if ingestion.core_status not in _INLINE_REPROCESS_STATES:
            raise HttpError(409, f"stato core non gestibile: {ingestion.core_status}")

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
                user_id=request.auth.user_id,
                client_session_id=ingestion.client_session_id,
                started_at=payload.started_at,
                ended_at=payload.ended_at,
            )

        trip = _get_or_create_inline_trip(ingestion)
        _materialize_inline_core(trip, payload)
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
        ingestion.save(
            update_fields=update_fields,
        )

        if ingestion.source_trip_id is not None:
            if payload.cutoff_source_timestamp is None:
                raise HttpError(400, "cutoff_source_timestamp richiesto per il replay")
            ended_at = ingestion.recording_closed_at or now
            regenerate_raw_and_queue_har(
                ingestion,
                ingestion.source_trip,
                shift=ended_at - payload.cutoff_source_timestamp,
                now=now,
                cutoff=payload.cutoff_source_timestamp,
            )

        return _inline_core_response(ingestion)


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
    response={202: CompleteOut, 409: dict},
    auth=mobile_bearer_auth,
)
def complete_core_ingestion(request, ingestion_id: int, payload: CompleteIn):
    ingestion = _get_owned_ingestion(request, ingestion_id)

    with transaction.atomic():
        ingestion = TripIngestion.objects.select_for_update().get(id=ingestion.id)
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
            _release_active_lock_for_failed_final(ingestion, now=timezone.now())
            return _core_failed_final_status()

        expected = _expected_part_keys(ingestion.expected_core_parts)
        if not expected:
            raise HttpError(409, "nessuna parte core attesa")
        confirmed = _confirmed_parts(ingestion)
        missing = [pk for pk in expected if pk not in confirmed]
        if missing:
            readable = ", ".join(f"{kind}#{seq}" for kind, seq in missing)
            raise HttpError(409, f"parti core mancanti: {readable}")

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

        if ingestion.trip_id is None:
            raise HttpError(409, "trip non materializzato per HAR finale")
        ingestion.manifest_sha256 = payload.manifest_sha256
        ingestion.raw_status = TripIngestion.PhaseStatus.QUEUED
        ingestion.queued_at = timezone.now()
        ingestion.error_message = ""
        ingestion.save(
            update_fields=[
                "manifest_sha256",
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

        transaction.on_commit(
            lambda: process_trip_har_final.delay(job.id, ingestion.id)
        )
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
