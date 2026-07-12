from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from django.contrib.gis.db.models.functions import Length
from django.contrib.gis.geos import LineString, Point
from django.utils import timezone

from ..models import GpsPoint, StateTransition, Trip, TripIngestion


class CoreMaterializationConflict(ValueError):
    """Il core e' valido, ma non puo' essere associato al Trip richiesto."""


@dataclass(frozen=True)
class CoreMaterializationResult:
    trip: Trip
    gps_points: int
    state_transitions: int
    path_points: int


@dataclass(frozen=True)
class MaterializedTripCounts:
    gps_points: int
    state_transitions: int
    path_points: int
    distance_meters: float


def materialized_trip_counts(trip: Trip | None) -> MaterializedTripCounts:
    if trip is None:
        return MaterializedTripCounts(
            gps_points=0,
            state_transitions=0,
            path_points=0,
            distance_meters=0,
        )
    gps_count = GpsPoint.objects.filter(trip=trip).count()
    transition_count = StateTransition.objects.filter(trip=trip).count()
    return MaterializedTripCounts(
        gps_points=gps_count,
        state_transitions=transition_count,
        path_points=gps_count,
        distance_meters=float(trip.distance_meters or 0),
    )

""" 
Crea il record trip, e i record gps e state transistion
"""
def materialize_inline_core_ingestion(
    ingestion: TripIngestion,
    payload: Any,
) -> CoreMaterializationResult:
    trip = _get_or_create_inline_trip(ingestion)
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
    transition_rows = [
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
    ]
    return _materialize_core_rows(
        trip,
        gps_rows=gps_rows,
        transition_rows=transition_rows,
    )

""" 
A partire da una lista di punti gps, costruisce una LineString 
"""
def build_trip_path(trip: Trip) -> int:
    """Deriva la LineString del viaggio dai GPS ordinati nel DB."""
    coords = [
        (point.x, point.y)
        for point in GpsPoint.objects.filter(trip=trip)
        .order_by("timestamp", "id")
        .values_list("point", flat=True)
    ]
    if len(set(coords)) < 2:
        trip.path = None
        trip.distance_meters = 0
        trip.save(update_fields=["path", "distance_meters", "updated_at"])
        return len(coords)

    trip.path = LineString(coords, srid=4326)
    trip.distance_meters = None
    trip.save(update_fields=["path", "distance_meters", "updated_at"])

    trip.distance_meters = _distance_meters_from_postgis(trip)
    trip.save(update_fields=["distance_meters", "updated_at"])
    return len(coords)

""" 
Inseriamo in un colpo solo tutto i gps poin e gli state transistion 
"""
def _materialize_core_rows(
    trip: Trip,
    *,
    gps_rows: list[GpsPoint],
    transition_rows: list[StateTransition],
) -> CoreMaterializationResult:
    StateTransition.objects.bulk_create(transition_rows, ignore_conflicts=True)
    GpsPoint.objects.bulk_create(gps_rows, ignore_conflicts=True)
    path_points = build_trip_path(trip)
    counts = materialized_trip_counts(trip)
    return CoreMaterializationResult(
        trip=trip,
        gps_points=counts.gps_points,
        state_transitions=counts.state_transitions,
        path_points=path_points,
    )

""" 
Creiamo la prima istanza del trip, essendo che questa funzione può essere chiamata 
più volte per politiche di retry, controlla e aggiorna i campi del trip se esiste già

Avviene prima di completare effettivamnete il core, ma per comodità metto comunque il suo 
stato a closed tanto il tutto è avvolto in una transazione atomica
"""
def _get_or_create_inline_trip(ingestion: TripIngestion) -> Trip:
    trip = (
        Trip.objects.select_for_update()
        .filter(client_session_id=ingestion.client_session_id)
        .first()
    )
    if trip is not None and trip.user_id not in {None, ingestion.user_id}:
        raise CoreMaterializationConflict(
            "client_session_id gia' associato a un altro utente"
        )
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
            reloaded_from_trip_id=ingestion.source_trip_id,
        )

    update_fields = ["updated_at"]
    if (
        trip.reloaded_from_trip_id is not None
        and trip.reloaded_from_trip_id != ingestion.source_trip_id
    ):
        raise CoreMaterializationConflict(
            "client_session_id gia' associato a un'altra sorgente"
        )
    if trip.user_id is None:
        trip.user_id = ingestion.user_id
        update_fields.append("user")
    if trip.reloaded_from_trip_id is None and ingestion.source_trip_id is not None:
        trip.reloaded_from_trip_id = ingestion.source_trip_id
        update_fields.append("reloaded_from_trip")
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

""" 
Usa la funzione di PostGIS per calcolare la distanza del viaggio, in metri, a partire dalla LineString
"""
def _distance_meters_from_postgis(trip: Trip) -> float:
    row = (
        Trip.objects.filter(pk=trip.pk)
        .annotate(path_length=Length("path"))
        .values("path_length")
        .get()
    )
    distance = row["path_length"]
    if distance is None:
        return 0
    return float(distance.m if hasattr(distance, "m") else distance)
