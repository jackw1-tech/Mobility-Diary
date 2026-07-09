from __future__ import annotations

import json
from typing import Any

from django.contrib.gis.db.models.functions import AsGeoJSON, Length
from django.db.models import BooleanField, Case, Count, Exists, OuterRef, Value, When

from ..models import PartKind, Trip, TripIngestion, TripIngestionPart


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
        .annotate(
            track_geojson=AsGeoJSON("path"),
            track_distance=Length("path"),
            point_count=Count("gps_points"),
        )
        .values("id", "track_geojson", "track_distance", "point_count")
        .first()
    )
    if row is None:
        return None

    distance = row["track_distance"]
    return {
        "trip_id": row["id"],
        "point_count": row["point_count"],
        "distance_meters": float(
            distance.m if hasattr(distance, "m") else distance or 0
        ),
        "geojson": (
            json.loads(row["track_geojson"])
            if row["track_geojson"] is not None
            else None
        ),
    }


def source_has_raw_sensor_evidence(source: Trip) -> bool:
    return TripIngestionPart.objects.filter(
        ingestion__trip=source,
        ingestion__raw_status=TripIngestion.PhaseStatus.COMPLETED,
        kind=PartKind.SENSOR_WINDOWS,
        received_at__isnull=False,
    ).exists()


def trip_has_reload_usage(trip: Trip) -> bool:
    return trip.reloads.exists() or trip.replay_ingestions.exists()


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
        "has_replay_ingestions": Exists(
            TripIngestion.objects.filter(source_trip=OuterRef("pk"))
        ),
        "has_raw_sensor_evidence": Exists(
            TripIngestionPart.objects.filter(
                ingestion__trip=OuterRef("pk"),
                ingestion__raw_status=TripIngestion.PhaseStatus.COMPLETED,
                kind=PartKind.SENSOR_WINDOWS,
                received_at__isnull=False,
            )
        ),
        "has_completed_ingestion": Exists(
            TripIngestion.objects.filter(
                trip=OuterRef("pk"),
                core_status=TripIngestion.PhaseStatus.COMPLETED,
                raw_status=TripIngestion.PhaseStatus.COMPLETED,
            )
        ),
    }


def _trip_can_delete(trip: Trip) -> bool:
    return not trip.has_reload_descendants and not trip.has_replay_ingestions


def _trip_can_toggle_reloadable(trip: Trip) -> bool:
    is_real = trip.reloaded_from_trip_id is None
    is_completed = trip.status in [Trip.Status.CLOSED, Trip.Status.PROCESSED]
    can_publish = not trip.is_reloadable and trip.has_raw_sensor_evidence
    can_withdraw = trip.is_reloadable and _trip_can_delete(trip)
    return is_real and is_completed and (can_publish or can_withdraw)


def _trip_can_edit_note(trip: Trip) -> bool:
    return trip.has_completed_ingestion


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
