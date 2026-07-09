from __future__ import annotations

import hashlib
import math
from dataclasses import dataclass
from datetime import datetime, timedelta
from datetime import timezone as dt_timezone

from django.contrib.gis.geos import Point
from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from ..ingestion.materialization import build_trip_path
from ..ingestion.selectors import active_ingestions_for_owner
from ..models import GpsPoint, StateTransition, Trip, TripIngestion
from ..replay_raw import regenerate_raw_and_queue_har
from ..selectors.trips import source_has_raw_sensor_evidence


class ReloadServiceError(ValueError):
    status_code = 409

    def __init__(self, message: str):
        super().__init__(message)
        self.message = message


class ReloadNotFound(ReloadServiceError):
    status_code = 404


class ReloadValidationError(ReloadServiceError):
    status_code = 422


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
    if active_ingestions_for_owner(user_id).exists():
        raise ReloadServiceError("viaggio in corso attivo")

    now = now or timezone.now()
    source = _owned_source_or_error(user_id, trip_id)
    client_session_id = _reload_client_session_id(
        user_id,
        source.id,
        reload_request_id,
    )

    with transaction.atomic():
        existing = (
            TripIngestion.objects.select_for_update()
            .filter(user_id=user_id, client_session_id=client_session_id)
            .first()
        )
        if existing is not None:
            if existing.trip_id is not None:
                return reload_response(existing)
            existing.delete()

        source = Trip.objects.select_for_update().get(id=source.id)
        if not _is_reloadable_source(source):
            raise ReloadServiceError("viaggio non ricaricabile")

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

        ingestion = TripIngestion.objects.create(
            user_id=user_id,
            client_session_id=client_session_id,
            device_id="reload",
            core_status=TripIngestion.PhaseStatus.COMPLETED,
            raw_status=TripIngestion.PhaseStatus.PENDING,
            core_ingestion_mode=TripIngestion.CoreIngestionMode.INLINE,
            expected_core_parts={},
            expected_raw_parts={},
            started_at=reload_start,
            ended_at=reload_end,
            completed_at=reload_end,
        )
        ingestion.raw_base_path = f"ingestions/{ingestion.id}/"
        ingestion.save(update_fields=["raw_base_path", "updated_at"])

        trip = Trip.objects.create(
            user_id=user_id,
            client_session_id=client_session_id,
            device_id="reload",
            status=Trip.Status.CLOSED,
            started_at=reload_start,
            ended_at=reload_end,
            reloaded_from_trip=source,
        )
        _copy_core_evidence(timeline, trip, shift)
        build_trip_path(trip)
        trip.refresh_from_db(fields=["path", "distance_meters"])

        ingestion.trip = trip
        ingestion.save(update_fields=["trip", "updated_at"])
        regenerate_raw_and_queue_har(ingestion, source, shift=shift, now=reload_end)
        return reload_response(ingestion)


def reload_response(ingestion: TripIngestion) -> dict:
    trip = ingestion.trip
    if trip is None:
        raise ReloadServiceError("reload senza trip materializzato")
    gps_count = GpsPoint.objects.filter(trip=trip).count()
    transition_count = StateTransition.objects.filter(trip=trip).count()
    return {
        "ingestion_id": ingestion.id,
        "trip_id": trip.id,
        "core_status": ingestion.core_status,
        "raw_status": ingestion.raw_status,
        "gps_points": gps_count,
        "state_transitions": transition_count,
        "path_points": gps_count,
        "distance_meters": float(trip.distance_meters or 0),
        "map_available": trip.path is not None,
    }


def _owned_source_or_error(user_id: int, trip_id: int) -> Trip:
    try:
        return Trip.objects.get(id=trip_id, user_id=user_id)
    except Trip.DoesNotExist as exc:
        raise ReloadNotFound("Trip non trovato") from exc


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
    return (
        Trip.objects.filter(user_id=user_id, started_at__lt=end)
        .filter(Q(ended_at__isnull=True) | Q(ended_at__gt=start))
        .exists()
    )


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
    busy_rows = (
        Trip.objects.filter(user_id=user_id, started_at__lt=now)
        .filter(Q(ended_at__isnull=True) | Q(ended_at__gt=window_start))
        .order_by("started_at")
        .values_list("started_at", "ended_at")
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
    GpsPoint.objects.bulk_create(
        [
            GpsPoint(
                trip=trip,
                timestamp=point.timestamp + shift,
                point=Point(point.longitude, point.latitude, srid=4326),
                speed_mps=point.speed_mps,
                accuracy_meters=point.accuracy_meters,
            )
            for point in timeline.points
        ],
        ignore_conflicts=True,
    )
    StateTransition.objects.bulk_create(
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
        ],
        ignore_conflicts=True,
    )
