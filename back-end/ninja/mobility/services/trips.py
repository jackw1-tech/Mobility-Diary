from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

from django.db import transaction
from django.utils import timezone
from django.utils.dateparse import parse_datetime

from shared.exceptions import ServiceError

from ..upload import storage
from ..models import Trip
from ..selectors import trips as trips_repository
from ..selectors.trips import (
    source_has_raw_sensor_evidence,
    trip_has_reload_usage,
    trip_list_item_by_id,
)


class TripServiceError(ServiceError):
    status_code = 409


class TripNotFound(TripServiceError):
    status_code = 404


class TripValidationError(TripServiceError):
    status_code = 422


@dataclass(frozen=True)
class RawTripFilterParams:
    started_from: str | None = None
    started_to: str | None = None
    status: str | None = None
    processed: str | None = None
    has_track: str | None = None


def _parse_datetime_filter(name: str, raw_value: str | None) -> datetime | None:
    if not raw_value:
        return None
    value = parse_datetime(raw_value)
    if value is None:
        raise TripValidationError(f"Filtro {name} non valido")
    return timezone.make_aware(value) if timezone.is_naive(value) else value


def _parse_bool_filter(name: str, raw_value: str | None) -> bool | None:
    if not raw_value:
        return None
    normalized = raw_value.lower()
    if normalized in {"true", "1", "yes"}:
        return True
    if normalized in {"false", "0", "no"}:
        return False
    raise TripValidationError(f"Filtro {name} non valido")


def parse_trip_filters(params: RawTripFilterParams) -> trips_repository.TripFilters:
    status = params.status
    if status and status not in Trip.Status.values:
        raise TripValidationError("Filtro status non valido")

    started_from = _parse_datetime_filter("from", params.started_from)
    started_to = _parse_datetime_filter("to", params.started_to)
    if (
        started_from is not None
        and started_to is not None
        and started_from > started_to
    ):
        raise TripValidationError("Intervallo temporale non valido")

    return trips_repository.TripFilters(
        started_from=started_from,
        started_to=started_to,
        status=status,
        processed=_parse_bool_filter("processed", params.processed),
        has_track=_parse_bool_filter("has_track", params.has_track),
    )


def update_trip_reloadable(
    *,
    user_id: int,
    trip_id: int,
    is_reloadable: bool,
) -> dict:
    with transaction.atomic():
        trip = _locked_owned_trip(user_id, trip_id)
        if trip.reloaded_from_trip_id is not None:
            raise TripServiceError("un viaggio derivato non puo' diventare ricaricabile")
        if trip.status not in [Trip.Status.CLOSED, Trip.Status.PROCESSED]:
            raise TripServiceError("solo un viaggio completato puo' diventare ricaricabile")

        if is_reloadable and not source_has_raw_sensor_evidence(trip):
            raise TripServiceError("telemetrie sorgente non disponibili")
        if not is_reloadable and trip.is_reloadable and trip_has_reload_usage(trip):
            raise TripServiceError("viaggio gia' usato come sorgente")

        trip.is_reloadable = is_reloadable
        trip.save(update_fields=["is_reloadable", "updated_at"])
    return trip_list_item_by_id(trip.id)


def update_trip_note(
    *,
    user_id: int,
    trip_id: int,
    note: str,
) -> dict:
    trip = _owned_trip(user_id, trip_id)
    if not trips_repository.trip_has_completed_upload(trip):
        raise TripServiceError("nota disponibile solo a viaggio completato")

    normalized_note = note.strip()
    if len(normalized_note) > 500:
        raise TripValidationError("nota troppo lunga")
    trip.note = normalized_note
    trip.save(update_fields=["note", "updated_at"])
    return trip_list_item_by_id(trip.id)


def delete_trip(
    *,
    user_id: int,
    trip_id: int,
) -> None:
    with transaction.atomic():
        trip = _locked_owned_trip(user_id, trip_id)
        if trip_has_reload_usage(trip):
            raise TripServiceError("viaggio gia' usato come sorgente")

        object_keys = trips_repository.trip_object_keys(trip)
        for object_key in object_keys:
            storage.delete_object(object_key)
        trips_repository.delete_trip_uploads(trip)
        trip.delete()


def _owned_trip(user_id: int, trip_id: int) -> Trip:
    trip = trips_repository.trip_by_id_for_user(trip_id, user_id)
    if trip is None:
        raise TripNotFound("Trip non trovato")
    return trip


def _locked_owned_trip(user_id: int, trip_id: int) -> Trip:
    trip = trips_repository.locked_trip_by_id_for_user(trip_id, user_id)
    if trip is None:
        raise TripNotFound("Trip non trovato")
    return trip
