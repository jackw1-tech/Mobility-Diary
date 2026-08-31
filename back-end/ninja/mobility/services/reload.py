from __future__ import annotations

import hashlib
import logging
import math
from dataclasses import dataclass
from datetime import datetime, timedelta
from datetime import timezone as dt_timezone
from time import perf_counter

from django.contrib.gis.geos import Point
from django.db import transaction
from django.utils import timezone

from shared.exceptions import ServiceError

from ..ingestion import selectors as ingestion_repository
from ..ingestion.materialization import build_trip_path, materialized_trip_counts
from ..models import GpsPoint, StateTransition, Trip, TripIngestion
from ..replay_raw import (
    ReplayRawError,
    ReplayStorageUnavailable,
    regenerate_raw_and_queue_har,
)
from ..selectors import trip_evidence as trip_evidence_repository
from ..selectors import trips as trips_repository
from ..selectors.trips import source_has_raw_sensor_evidence

logger = logging.getLogger(__name__)


class ReloadServiceError(ServiceError):
    status_code = 409


class ReloadNotFound(ReloadServiceError):
    status_code = 404


class ReloadValidationError(ReloadServiceError):
    status_code = 422


class ReloadStorageUnavailable(ReloadServiceError):
    status_code = 503


@dataclass(frozen=True)
class ReloadTimeline:
    points: list[GpsPoint]
    transitions: list[StateTransition]
    start: datetime
    end: datetime


def reload_slots_for_trip(
    *,
    user_id: int,
    trip_id: int,
    days: int,
    step_minutes: int,
    limit: int,
    now: datetime | None = None,
) -> dict:
    now = now or timezone.now()
    source = _reloadable_source_or_error(user_id, trip_id)
    if not source_has_raw_sensor_evidence(source):
        raise ReloadServiceError("telemetrie sorgente non disponibili")
    timeline = _source_timeline(source)
    duration = timeline.end - timeline.start
    if duration <= timedelta(0):
        raise ReloadServiceError("durata viaggio ricaricabile non valida")
    return {
        "source_trip_id": source.id,
        "duration_seconds": int(duration.total_seconds()),
        "slots": _reload_slot_candidates(
            user_id=user_id,
            duration=duration,
            now=now,
            days=days,
            step_minutes=step_minutes,
            limit=limit,
        ),
    }


def reload_trip_from_source(
    *,
    user_id: int,
    trip_id: int,
    reload_request_id: str,
    scheduled_start_at: datetime | None,
    now: datetime | None = None,
) -> dict:
    if not reload_request_id:
        raise ReloadValidationError("reload_request_id richiesto")
    if ingestion_repository.active_ingestions_for_owner(user_id).exists():
        raise ReloadServiceError("viaggio in corso attivo")

    task_started = perf_counter()
    phase_timings_ms: dict[str, float] = {}
    ingestion_id: int | None = None
    result_trip_id: int | None = None

    now = now or timezone.now()
    source = _owned_source_or_error(user_id, trip_id)
    client_session_id = _reload_client_session_id(
        user_id,
        source.id,
        reload_request_id,
    )

    try:
        with transaction.atomic():
            lookup_started = perf_counter()
            existing = ingestion_repository.locked_ingestion_by_client_session(
                user_id, client_session_id
            )
            if existing is not None:
                if existing.trip_id is not None:
                    phase_timings_ms["idempotent_lookup"] = _elapsed_ms(lookup_started)
                    phase_timings_ms["task_total"] = _elapsed_ms(task_started)
                    _log_reload_timing(
                        "idempotent_hit",
                        ingestion_id=existing.id,
                        trip_id=existing.trip_id,
                        phase_timings_ms=phase_timings_ms,
                    )
                    return reload_response(existing)
                ingestion_repository.delete_ingestion(existing)

            source = trips_repository.locked_trip_by_id(source.id)
            if not _is_reloadable_source(source):
                raise ReloadServiceError("viaggio non ricaricabile")
            phase_timings_ms["lookup_and_lock"] = _elapsed_ms(lookup_started)

            timeline_started = perf_counter()
            timeline = _source_timeline(source)
            duration = timeline.end - timeline.start
            reload_end = now
            if scheduled_start_at is None:
                reload_start = reload_end - duration
            else:
                reload_start = scheduled_start_at
                reload_end = reload_start + duration
                _ensure_reload_slot_available(user_id, reload_start, reload_end, now)
            shift = reload_start - timeline.start
            phase_timings_ms["build_timeline"] = _elapsed_ms(timeline_started)

            create_started = perf_counter()
            ingestion = ingestion_repository.create_ingestion_with_fields(
                user_id=user_id,
                client_session_id=client_session_id,
                device_id="reload",
                core_status=TripIngestion.PhaseStatus.COMPLETED,
                raw_status=TripIngestion.PhaseStatus.PENDING,
                expected_raw_parts=0,
                started_at=reload_start,
                ended_at=reload_end,
                completed_at=reload_end,
            )
            ingestion.raw_base_path = f"ingestions/{ingestion.id}/"
            ingestion.save(update_fields=["raw_base_path", "updated_at"])
            ingestion_id = ingestion.id

            trip = trips_repository.create_trip(
                user_id=user_id,
                client_session_id=client_session_id,
                device_id="reload",
                status=Trip.Status.CLOSED,
                started_at=reload_start,
                ended_at=reload_end,
                reloaded_from_trip=source,
            )
            result_trip_id = trip.id
            phase_timings_ms["create_records"] = _elapsed_ms(create_started)

            copy_started = perf_counter()
            _copy_core_evidence(timeline, trip, shift)
            build_trip_path(trip)
            trip.refresh_from_db(fields=["path", "distance_meters"])
            phase_timings_ms["copy_core_evidence"] = _elapsed_ms(copy_started)

            ingestion.trip = trip
            ingestion.save(update_fields=["trip", "updated_at"])

            regen_started = perf_counter()
            try:
                regenerate_raw_and_queue_har(
                    ingestion, source, shift=shift, now=reload_end
                )
            finally:
                phase_timings_ms["regenerate_raw_and_queue_har"] = _elapsed_ms(
                    regen_started
                )
            phase_timings_ms["task_total"] = _elapsed_ms(task_started)
            _log_reload_timing(
                "completed",
                ingestion_id=ingestion_id,
                trip_id=result_trip_id,
                phase_timings_ms=phase_timings_ms,
            )
            return reload_response(ingestion)
    except ReplayStorageUnavailable as exc:
        phase_timings_ms["task_total_until_error"] = _elapsed_ms(task_started)
        _log_reload_timing(
            "failed_storage",
            ingestion_id=ingestion_id,
            trip_id=result_trip_id,
            phase_timings_ms=phase_timings_ms,
            error=exc.message,
        )
        raise ReloadStorageUnavailable(exc.message) from exc
    except ReplayRawError as exc:
        phase_timings_ms["task_total_until_error"] = _elapsed_ms(task_started)
        _log_reload_timing(
            "failed_raw",
            ingestion_id=ingestion_id,
            trip_id=result_trip_id,
            phase_timings_ms=phase_timings_ms,
            error=exc.message,
        )
        raise ReloadServiceError(exc.message) from exc
    except Exception as exc:
        phase_timings_ms["task_total_until_error"] = _elapsed_ms(task_started)
        _log_reload_timing(
            "failed_unexpected",
            ingestion_id=ingestion_id,
            trip_id=result_trip_id,
            phase_timings_ms=phase_timings_ms,
            error=str(exc),
        )
        raise


def reload_response(ingestion: TripIngestion) -> dict:
    trip = ingestion.trip
    if trip is None:
        raise ReloadServiceError("reload senza trip materializzato")
    counts = materialized_trip_counts(trip)
    return {
        "ingestion_id": ingestion.id,
        "trip_id": trip.id,
        "core_status": ingestion.core_status,
        "raw_status": ingestion.raw_status,
        "gps_points": counts.gps_points,
        "state_transitions": counts.state_transitions,
        "path_points": counts.path_points,
        "distance_meters": counts.distance_meters,
        "map_available": trip.path is not None,
    }


def _owned_source_or_error(user_id: int, trip_id: int) -> Trip:
    trip = trips_repository.trip_by_id_for_user(trip_id, user_id)
    if trip is None:
        raise ReloadNotFound("Trip non trovato")
    return trip


def _reloadable_source_or_error(user_id: int, trip_id: int) -> Trip:
    source = _owned_source_or_error(user_id, trip_id)
    if not _is_reloadable_source(source):
        raise ReloadServiceError("viaggio non ricaricabile")
    return source


def _is_reloadable_source(source: Trip) -> bool:
    return source.is_reloadable and source.status in [
        Trip.Status.CLOSED,
        Trip.Status.PROCESSED,
    ]


def _reload_client_session_id(user_id: int, source_trip_id: int, request_id: str) -> str:
    key = f"{user_id}:{source_trip_id}:{request_id}".encode("utf-8")
    return f"reload-{hashlib.sha256(key).hexdigest()[:57]}"


def _source_timeline(source: Trip) -> ReloadTimeline:
    source_points = list(source.gps_points.order_by("timestamp"))
    source_transitions = list(source.state_transitions.order_by("timestamp"))
    source_timestamps = [point.timestamp for point in source_points] + [
        transition.timestamp for transition in source_transitions
    ]
    if not source_timestamps:
        raise ReloadServiceError("viaggio ricaricabile senza evidenza core")

    source_start = source.started_at or min(source_timestamps)
    source_end = source.ended_at or max(source_timestamps)
    if source_end < source_start:
        raise ReloadServiceError("durata viaggio ricaricabile non valida")
    return ReloadTimeline(
        points=source_points,
        transitions=source_transitions,
        start=source_start,
        end=source_end,
    )


def _user_trip_overlaps(user_id: int, start: datetime, end: datetime) -> bool:
    return trips_repository.trip_overlaps_window(user_id, start=start, end=end)


def _ensure_reload_slot_available(
    user_id: int,
    start: datetime,
    end: datetime,
    now: datetime,
) -> None:
    if end > now:
        raise ReloadServiceError("scegli uno slot nel passato")
    if _user_trip_overlaps(user_id, start, end):
        raise ReloadServiceError("slot sovrapposto a un viaggio esistente")


def _ceil_to_step(value: datetime, step_minutes: int) -> datetime:
    step_seconds = step_minutes * 60
    timestamp = math.ceil(value.timestamp() / step_seconds) * step_seconds
    return datetime.fromtimestamp(timestamp, tz=dt_timezone.utc)


def _reload_slot_candidates(
    *,
    user_id: int,
    duration: timedelta,
    now: datetime,
    days: int,
    step_minutes: int,
    limit: int,
) -> list[dict[str, datetime]]:
    window_start = now - timedelta(days=max(1, min(days, 30)))
    step_minutes = max(5, min(step_minutes, 60))
    limit = max(1, min(limit, 500))
    busy_rows = trips_repository.trip_busy_intervals(
        user_id, before=now, active_after=window_start
    )
    busy = [
        (max(start, window_start), min(end or now, now))
        for start, end in busy_rows
        if start and max(start, window_start) < min(end or now, now)
    ]
    free: list[tuple[datetime, datetime]] = []
    cursor = window_start
    for start, end in busy:
        if start > cursor:
            free.append((cursor, start))
        if end > cursor:
            cursor = end
    if cursor < now:
        free.append((cursor, now))

    slots: list[dict[str, datetime]] = []
    for free_start, free_end in free:
        candidate = _ceil_to_step(free_start, step_minutes)
        while candidate + duration <= free_end:
            slots.append(
                {
                    "started_at": candidate,
                    "ended_at": candidate + duration,
                }
            )
            candidate += timedelta(minutes=step_minutes)
    return list(reversed(slots[-limit:]))


def _copy_core_evidence(
    timeline: ReloadTimeline,
    trip: Trip,
    shift: timedelta,
) -> None:
    trip_evidence_repository.bulk_create_gps_points(
        [
            GpsPoint(
                trip=trip,
                timestamp=point.timestamp + shift,
                point=Point(point.longitude, point.latitude, srid=4326),
                speed_mps=point.speed_mps,
                accuracy_meters=point.accuracy_meters,
            )
            for point in timeline.points
        ]
    )
    trip_evidence_repository.bulk_create_state_transitions(
        [
            StateTransition(
                trip=trip,
                timestamp=transition.timestamp + shift,
                from_state=transition.from_state,
                to_state=transition.to_state,
                reason=transition.reason,
                sigma=transition.sigma,
                speed_mps=transition.speed_mps,
            )
            for transition in timeline.transitions
        ]
    )


def _elapsed_ms(started_at: float) -> float:
    return (perf_counter() - started_at) * 1000


def _rounded(values: dict[str, float]) -> dict[str, float]:
    return {key: round(value, 2) for key, value in values.items()}


def _percentage(value: float, total_ms: float) -> float:
    if total_ms <= 0:
        return 0.0
    return round((value / total_ms) * 100, 2)


def _percentages(values: dict[str, float], total_ms: float) -> dict[str, float]:
    return {key: _percentage(value, total_ms) for key, value in values.items()}


def _log_reload_timing(
    status: str,
    *,
    ingestion_id: int | None,
    trip_id: int | None,
    phase_timings_ms: dict[str, float],
    error: str | None = None,
) -> None:
    total_ms = phase_timings_ms.get("task_total") or phase_timings_ms.get(
        "task_total_until_error"
    ) or sum(
        value
        for key, value in phase_timings_ms.items()
        if not key.startswith("task_total")
    )

    log_payload = {
        "status": status,
        "ingestion_id": ingestion_id,
        "trip_id": trip_id,
        "total_ms": round(total_ms, 2),
        "phases_ms": _rounded(phase_timings_ms),
        "phases_pct": _percentages(phase_timings_ms, total_ms),
    }
    if error:
        log_payload["error"] = error

    logger.info("[RELOAD-TRIP-TIMING] %s", log_payload)
