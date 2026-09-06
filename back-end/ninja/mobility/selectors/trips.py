from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from django.contrib.gis.db.models.functions import AsGeoJSON, Length
from django.db.models import (
    BooleanField,
    Case,
    Exists,
    OuterRef,
    Q,
    Value,
    When,
)

from ..upload import selectors as upload_selectors
from ..models import GpsPoint, SensorWindow, Trip, TripUpload, TripUploadPart


@dataclass(frozen=True)
class TripFilters:
    """Filtri gia' validati per la lista Viaggi della dashboard web."""

    started_from: datetime | None = None
    started_to: datetime | None = None
    status: str | None = None
    processed: bool | None = None
    has_track: bool | None = None


def trip_by_id_for_user(trip_id: int, user_id: int) -> Trip | None:
    return Trip.objects.filter(id=trip_id, user_id=user_id).first()


def create_trip(**fields) -> Trip:
    """Crea un Trip con i campi indicati (nessuna decisione: la sceglie il chiamante)."""
    return Trip.objects.create(**fields)


def locked_trip_by_client_session(client_session_id: str) -> Trip | None:
    return (
        Trip.objects.select_for_update()
        .filter(client_session_id=client_session_id)
        .first()
    )


def trip_path_length_meters(trip: Trip) -> float:
    row = (
        Trip.objects.filter(pk=trip.pk)
        .annotate(path_length=Length("path"))
        .values("path_length")
        .get()
    )
    distance = row["path_length"]
    if distance is None:
        return 0.0
    return float(distance.m if hasattr(distance, "m") else distance)


def locked_trip_by_id_for_user(trip_id: int, user_id: int) -> Trip | None:
    return (
        Trip.objects.select_for_update()
        .filter(id=trip_id, user_id=user_id)
        .first()
    )


def trips_queryset_for_user(user_id: int):
    return Trip.objects.filter(user_id=user_id)


def trip_has_completed_upload(trip: Trip) -> bool:
    return TripUpload.objects.filter(
        trip=trip,
        core_status=TripUpload.PhaseStatus.COMPLETED,
        raw_status=TripUpload.PhaseStatus.COMPLETED,
    ).exists()


def trip_object_keys(trip: Trip) -> list[str]:
    """Object key S3 delle telemetrie del viaggio (SensorWindow + parti raw)."""
    sensor_keys = (
        SensorWindow.objects.filter(trip=trip)
        .exclude(object_key="")
        .values_list("object_key", flat=True)
    )
    upload_keys = TripUploadPart.objects.filter(
        upload__trip=trip
    ).values_list("object_key", flat=True)
    return sorted({key for key in [*sensor_keys, *upload_keys] if key})


def delete_trip_uploads(trip: Trip) -> None:
    TripUpload.objects.filter(trip=trip).delete()


def apply_trip_filters(queryset, filters: TripFilters):
    """Applica filtri gia' validati alla queryset Trip (nessuna decisione qui)."""
    if filters.started_from:
        queryset = queryset.filter(started_at__gte=filters.started_from)
    if filters.started_to:
        queryset = queryset.filter(started_at__lte=filters.started_to)
    if filters.status:
        queryset = queryset.filter(status=filters.status)
    if filters.processed is not None:
        queryset = (
            queryset.filter(status=Trip.Status.PROCESSED)
            if filters.processed
            else queryset.exclude(status=Trip.Status.PROCESSED)
        )
    if filters.has_track is not None:
        queryset = queryset.filter(path__isnull=not filters.has_track)
    return queryset


def web_trip_list_projection(queryset) -> list[dict[str, Any]]:
    """Proiezione Viaggio per la dashboard web (id/stato/distanza/traccia)."""
    return list(
        queryset.annotate(
            processed=Case(
                When(status=Trip.Status.PROCESSED, then=Value(True)),
                default=Value(False),
                output_field=BooleanField(),
            ),
            has_track=Case(
                When(path__isnull=False, then=Value(True)),
                default=Value(False),
                output_field=BooleanField(),
            ),
        )
        .order_by("-started_at", "-id")
        .values(
            "id",
            "started_at",
            "ended_at",
            "status",
            "distance_meters",
            "processed",
            "has_track",
        )
    )


def trip_overlaps_window(
    user_id: int,
    *,
    start,
    end,
    exclude_client_session_id: str | None = None,
) -> bool:
    """True se l'utente ha gia' un Trip che copre (start, end).

    Query unica per questa esigenza: prima era ripetuta quasi identica in
    `mobility.services.reload._user_trip_overlaps` e in
    `mobility.upload.services._validate_replay_slot`.
    """
    queryset = Trip.objects.filter(user_id=user_id, started_at__lt=end).filter(
        Q(ended_at__isnull=True) | Q(ended_at__gt=start)
    )
    if exclude_client_session_id:
        queryset = queryset.exclude(client_session_id=exclude_client_session_id)
    return queryset.exists()

# Prende i viaggi del passato (started_at__lt < ora)
# e che finiscono in nei giorni in cui mi interessa trovare uno slot (ended_at > oggi - 14 giorni )
# restituisce solo tuple di date
def trip_busy_intervals(user_id: int, *, before, active_after):
    return (
        Trip.objects.filter(user_id=user_id, started_at__lt=before)
        .filter(Q(ended_at__isnull=True) | Q(ended_at__gt=active_after))
        .order_by("started_at")
        .values_list("started_at", "ended_at")
    )


def reloadable_source_trip_exists(source_trip_id: int, user_id: int) -> bool:
    return Trip.objects.filter(
        id=source_trip_id,
        user_id=user_id,
        is_reloadable=True,
        status__in=[Trip.Status.CLOSED, Trip.Status.PROCESSED],
    ).exists()


def trip_diary_enrichment_failed(trip_id: int, user_id: int) -> bool:
    """True se l'arricchimento del diario (fase raw) e' fallito in modo definitivo."""
    return TripUpload.objects.filter(
        trip_id=trip_id,
        user_id=user_id,
        raw_status=TripUpload.PhaseStatus.FAILED_FINAL,
    ).exists()


def trip_list_items_for_user(user_id: int) -> list[dict[str, Any]]:
    return _trip_list_items(Trip.objects.filter(user_id=user_id))


def reloadable_trip_list_items_for_user(user_id: int) -> list[dict[str, Any]]:
    return _trip_list_items(
        Trip.objects.filter(
            user_id=user_id,
            is_reloadable=True,
            status__in=[Trip.Status.CLOSED, Trip.Status.PROCESSED],
        )
    )


def trip_list_item_by_id(trip_id: int) -> dict[str, Any]:
    trip = Trip.objects.filter(id=trip_id).annotate(**_trip_list_annotations()).get()
    return _trip_list_item(trip)


def trip_track_for_user(trip_id: int, user_id: int) -> dict[str, Any] | None:
    row = (
        Trip.objects.filter(pk=trip_id, user_id=user_id)
        .annotate(track_geojson=AsGeoJSON("path"))
        .values("id", "track_geojson", "distance_meters")
        .first()
    )
    if row is None:
        return None

    return {
        "trip_id": row["id"],
        "point_count": GpsPoint.objects.filter(trip_id=trip_id).count(),
        "distance_meters": float(row["distance_meters"] or 0),
        "geojson": (
            json.loads(row["track_geojson"])
            if row["track_geojson"] is not None
            else None
        ),
    }


def source_has_raw_sensor_evidence(source: Trip) -> bool:
    return upload_selectors.completed_raw_parts_for_trip(source).exists()


def trip_has_reload_usage(trip: Trip) -> bool:
    return trip.reloads.exists() or trip.replay_uploads.exists()


def _trip_list_items(queryset) -> list[dict[str, Any]]:
    rows = queryset.annotate(**_trip_list_annotations()).order_by("-started_at")
    return [_trip_list_item(row) for row in rows]


def _trip_list_annotations():
    return {
        "has_track": Case(
            When(path__isnull=False, then=Value(True)),
            default=Value(False),
            output_field=BooleanField(),
        ),
        "has_reload_descendants": Exists(
            Trip.objects.filter(reloaded_from_trip=OuterRef("pk"))
        ),
        "has_replay_uploads": Exists(
            TripUpload.objects.filter(source_trip=OuterRef("pk"))
        ),
        "has_raw_sensor_evidence": Exists(
            TripUploadPart.objects.filter(
                upload__trip=OuterRef("pk"),
                upload__raw_status=TripUpload.PhaseStatus.COMPLETED,
                received_at__isnull=False,
            )
        ),
        "has_completed_upload": Exists(
            TripUpload.objects.filter(
                trip=OuterRef("pk"),
                core_status=TripUpload.PhaseStatus.COMPLETED,
                raw_status=TripUpload.PhaseStatus.COMPLETED,
            )
        ),
    }


def _trip_can_delete(trip: Trip) -> bool:
    return not trip.has_reload_descendants and not trip.has_replay_uploads


def _trip_can_toggle_reloadable(trip: Trip) -> bool:
    is_real = trip.reloaded_from_trip_id is None
    is_completed = trip.status in [Trip.Status.CLOSED, Trip.Status.PROCESSED]
    can_publish = not trip.is_reloadable and trip.has_raw_sensor_evidence
    can_withdraw = trip.is_reloadable and _trip_can_delete(trip)
    return is_real and is_completed and (can_publish or can_withdraw)


def _trip_can_edit_note(trip: Trip) -> bool:
    return trip.has_completed_upload


def _trip_list_item(trip: Trip) -> dict[str, Any]:
    return {
        "id": trip.id,
        "started_at": trip.started_at,
        "ended_at": trip.ended_at,
        "status": trip.status,
        "distance_meters": trip.distance_meters,
        "note": trip.note,
        "has_track": trip.has_track,
        "is_reloadable": trip.is_reloadable,
        "is_derived": trip.reloaded_from_trip_id is not None,
        "can_delete": _trip_can_delete(trip),
        "can_toggle_reloadable": _trip_can_toggle_reloadable(trip),
        "can_edit_note": _trip_can_edit_note(trip),
    }
