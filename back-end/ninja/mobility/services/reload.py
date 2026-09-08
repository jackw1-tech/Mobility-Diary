from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import datetime, timedelta
from datetime import timezone as dt_timezone

from django.contrib.gis.geos import Point
from django.db import transaction
from django.utils import timezone

from shared.exceptions import ServiceError

from ..tasks import prepare_reloaded_trip_raw
from ..upload import selectors as upload_repository
from ..upload import storage
from ..upload.materialization import build_trip_path, materialized_trip_counts
from ..models import GpsPoint, StateTransition, Trip, TripUpload
from ..replay_raw import (
    ReplayRawError,
    ReplayStorageUnavailable,
)
from ..selectors import trip_evidence as trip_evidence_repository
from ..selectors import trips as trips_repository
from ..selectors.trips import source_has_raw_sensor_evidence


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


## Costruisco la risposta degli slot disponibili
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
    if upload_repository.active_uploads_for_owner(user_id).exists():
        raise ReloadServiceError("viaggio in corso attivo")

    now = now or timezone.now()
    client_session_id = f"reload-{reload_request_id}"

    try:
        with transaction.atomic():
            existing = upload_repository.locked_upload_by_client_session(
                user_id, client_session_id
            )
            if existing is not None:
                # Il viaggio era già stato completato, ma il mobile non ha
                # ricevuto la risposta.
                if existing.trip_id is not None:
                    return reload_response(existing)
                # Tentativo incompleto: elimino e ricomincio.
                existing.delete()

            source = trips_repository.locked_trip_by_id_for_user(
                trip_id, user_id
            )
            if source is None:
                raise ReloadNotFound("Trip non trovato")
            if not _is_reloadable_source(source):
                raise ReloadServiceError("viaggio non ricaricabile")

            _ensure_source_raw_objects_available(source)

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

            upload = upload_repository.create_reloaded_upload(
                user_id=user_id,
                client_session_id=client_session_id,
                started_at=reload_start,
                ended_at=reload_end,
                source_trip=source,
            )
            upload.raw_base_path = f"uploads/{upload.id}/"
            upload.save(update_fields=["raw_base_path", "updated_at"])

            trip = trips_repository.create_trip(
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
            trip.refresh_from_db(fields=["path", "distance_meters"]) #aggiorno l'oggetto trip dopo l update di build_trip_path

            upload.trip = trip
            upload.save(update_fields=["trip", "updated_at"])

            shift_us = _timedelta_microseconds(shift)
            transaction.on_commit( # Prima Django crea finisce la transazione -> Commit -> A commit riuscito parte il task
                lambda: prepare_reloaded_trip_raw.delay(
                    upload.id,
                    source.id,
                    shift_us,
                )
            )
            return reload_response(upload)
    except ReplayStorageUnavailable as exc:
        raise ReloadStorageUnavailable(exc.message) from exc
    except ReplayRawError as exc:
        raise ReloadServiceError(exc.message) from exc


def reload_response(upload: TripUpload) -> dict:
    trip = upload.trip
    if trip is None:
        raise ReloadServiceError("reload senza trip materializzato")
    counts = materialized_trip_counts(trip)
    return {
        "upload_id": upload.id,
        "trip_id": trip.id,
        "core_status": upload.core_status,
        "raw_status": upload.raw_status,
        "gps_points": counts.gps_points,
        "state_transitions": counts.state_transitions,
        "path_points": counts.path_points,
        "distance_meters": counts.distance_meters,
        "map_available": trip.path is not None,
    }

# Controlla il flag is reloadble del trip
def _is_reloadable_source(source: Trip) -> bool:
    return source.is_reloadable and source.status in [
        Trip.Status.CLOSED,
        Trip.Status.PROCESSED,
    ]

# Funzione che cerca il trip e indica se è ricaricabile
def _reloadable_source_or_error(user_id: int, trip_id: int) -> Trip:
    source = trips_repository.trip_by_id_for_user(trip_id, user_id)
    if source is None:
        raise ReloadNotFound("Trip non trovato")
    if not _is_reloadable_source(source):
        raise ReloadServiceError("viaggio non ricaricabile")
    return source

# Parto da un viaggio e restituisco un oggetto che contiene lista di punti, lista di transizioni, start e end di quel trip
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



# Controllo finale extra se lo slot selezionato è effettivamente disponibile
def _ensure_reload_slot_available(
    user_id: int,
    start: datetime,
    end: datetime,
    now: datetime,
) -> None:
    if end > now:
        raise ReloadServiceError("scegli uno slot nel passato")
    if trips_repository.trip_overlaps_window(user_id, start=start, end=end):
        raise ReloadServiceError("slot sovrapposto a un viaggio esistente")


#Prende un orarioe lo arrotonda al prossimo "step" da 15 minuti
def _round_up_to_next_step(moment: datetime, step_minutes: int) -> datetime:
    step_seconds = step_minutes * 60
    timestamp = math.ceil(moment.timestamp() / step_seconds) * step_seconds
    return datetime.fromtimestamp(timestamp, tz=dt_timezone.utc)




# Creo una lista di intervalli che non posso usare nei 14 giorni
def _busy_intervals_within_window(
    busy_rows,
    *,
    window_start: datetime,
    now: datetime,
) -> list[tuple[datetime, datetime]]:
    intervals_in_window = []
    for trip_start, trip_end in busy_rows:
        if not trip_start:
            continue
        overlap_start = max(trip_start, window_start)
        overlap_end = min(trip_end or now, now)
        if overlap_start < overlap_end:
            intervals_in_window.append((overlap_start, overlap_end))
    return intervals_in_window

## Per tutti e 14 giorni, gli va a levare gli slot non disponibili
def _free_intervals(
    busy: list[tuple[datetime, datetime]],
    *,
    window_start: datetime,
    now: datetime,
) -> list[tuple[datetime, datetime]]:
    free_intervals = []
    next_free_start = window_start
    for busy_start, busy_end in busy:
        if busy_start > next_free_start:
            free_intervals.append((next_free_start, busy_start))
        next_free_start = max(next_free_start, busy_end)
    if next_free_start < now:
        free_intervals.append((next_free_start, now))
    return free_intervals


#Per ogni singolo buco libero trovato nei 14 giorni, ci trovo dei possibili slot considerando la durata del trip
def _candidate_slots_in_interval(
    free_start: datetime,
    free_end: datetime,
    *,
    duration: timedelta,
    step_minutes: int,
) -> list[dict[str, datetime]]:
    slots = []
    candidate = _round_up_to_next_step(free_start, step_minutes)
    while candidate + duration <= free_end:
        slots.append({"started_at": candidate, "ended_at": candidate + duration})
        candidate += timedelta(minutes=step_minutes)
    return slots

# Sapendo quanto è la duration del viaggio, calcolo gli slot disponibili
def _reload_slot_candidates(
    *,
    user_id: int,
    duration: timedelta,
    now: datetime,
    days: int,
    step_minutes: int,
    limit: int,
) -> list[dict[str, datetime]]:
    window_start = now - timedelta(days)

    busy_rows = trips_repository.trip_busy_intervals(
        user_id, before=now, active_after=window_start
    )
    busy = _busy_intervals_within_window(busy_rows, window_start=window_start, now=now)
    free = _free_intervals(busy, window_start=window_start, now=now)

    slots = [
        slot
        for free_start, free_end in free
        for slot in _candidate_slots_in_interval(
            free_start, free_end, duration=duration, step_minutes=step_minutes
        )
    ]
    return list(reversed(slots[-limit:]))


# Per il nuovo trip, inserisce tutti i punti gps e i cambiamenti di stato del vecchio viaggio con i timestamp shiftati
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
                sigma=transition.sigma,
                speed_mps=transition.speed_mps,
            )
            for transition in timeline.transitions
        ]
    )

#Recupera tutte le righe TripUploadPart e con una chiamata head controlla se i dati sono presenti nello storage
def _ensure_source_raw_objects_available(source: Trip) -> int:
    parts = list(upload_repository.completed_raw_parts_for_trip(source))
    if not parts:
        raise ReloadServiceError("telemetrie sorgente non disponibili")
    try:
        missing = [
            part.object_key
            for part in parts
            if storage.head_object(part.object_key) is None
        ]
    except Exception as exc:
        raise ReloadStorageUnavailable(
            "storage ricaricamento non disponibile"
        ) from exc
    if missing:
        raise ReloadServiceError("telemetrie sorgente non disponibili")
    return len(parts)


def _timedelta_microseconds(value: timedelta) -> int:
    return (
        value.days * 24 * 60 * 60 * 1_000_000
        + value.seconds * 1_000_000
        + value.microseconds
    )
