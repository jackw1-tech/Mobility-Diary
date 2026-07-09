from __future__ import annotations

from django.db import transaction

from ..ingestion import storage
from ..models import SensorWindow, Trip, TripIngestion, TripIngestionPart
from ..selectors.trips import (
    source_has_raw_sensor_evidence,
    trip_has_reload_usage,
    trip_list_item_by_id,
)


class TripServiceError(ValueError):
    status_code = 409

    def __init__(self, message: str):
        super().__init__(message)
        self.message = message


class TripNotFound(TripServiceError):
    status_code = 404


class TripValidationError(TripServiceError):
    status_code = 422


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
    if not TripIngestion.objects.filter(
        trip=trip,
        core_status=TripIngestion.PhaseStatus.COMPLETED,
        raw_status=TripIngestion.PhaseStatus.COMPLETED,
    ).exists():
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

        object_keys = _trip_object_keys(trip)
        for object_key in object_keys:
            storage.delete_object(object_key)
        TripIngestion.objects.filter(trip=trip).delete()
        trip.delete()


def _owned_trip(user_id: int, trip_id: int) -> Trip:
    try:
        return Trip.objects.get(id=trip_id, user_id=user_id)
    except Trip.DoesNotExist as exc:
        raise TripNotFound("Trip non trovato") from exc


def _locked_owned_trip(user_id: int, trip_id: int) -> Trip:
    try:
        return Trip.objects.select_for_update().get(id=trip_id, user_id=user_id)
    except Trip.DoesNotExist as exc:
        raise TripNotFound("Trip non trovato") from exc


def _trip_object_keys(trip: Trip) -> list[str]:
    sensor_keys = (
        SensorWindow.objects.filter(trip=trip)
        .exclude(object_key="")
        .values_list("object_key", flat=True)
    )
    ingestion_keys = TripIngestionPart.objects.filter(
        ingestion__trip=trip
    ).values_list("object_key", flat=True)
    return sorted({key for key in [*sensor_keys, *ingestion_keys] if key})
