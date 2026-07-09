from __future__ import annotations

import gzip
import json
from dataclasses import dataclass
from typing import Any

from django.contrib.gis.db.models.functions import Length
from django.contrib.gis.geos import LineString, Point
from django.utils import timezone
from django.utils.dateparse import parse_datetime

from ..models import GpsPoint, PartKind, StateTransition, Trip, TripIngestion
from . import storage

try:
    import orjson
except ModuleNotFoundError:  # pragma: no cover - fallback per ambienti non rebuildati
    orjson = None


class CoreMaterializationConflict(ValueError):
    """Il core e' valido, ma non puo' essere associato al Trip richiesto."""


class InvalidCoreIngestionPayload(ValueError):
    """Un blob core e' leggibile dallo storage ma non rispetta il contratto."""


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
        count_persisted_rows=True,
    )


def materialize_part_based_core_ingestion(
    ingestion: TripIngestion,
) -> CoreMaterializationResult:
    trip = _get_or_create_part_based_trip(ingestion)
    gps_rows = _part_gps_rows(trip, ingestion)
    transition_rows = _part_transition_rows(trip, ingestion)
    return _materialize_core_rows(
        trip,
        gps_rows=gps_rows,
        transition_rows=transition_rows,
        count_persisted_rows=False,
    )


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


def _materialize_core_rows(
    trip: Trip,
    *,
    gps_rows: list[GpsPoint],
    transition_rows: list[StateTransition],
    count_persisted_rows: bool,
) -> CoreMaterializationResult:
    StateTransition.objects.bulk_create(transition_rows, ignore_conflicts=True)
    GpsPoint.objects.bulk_create(gps_rows, ignore_conflicts=True)
    path_points = build_trip_path(trip)
    if count_persisted_rows:
        counts = materialized_trip_counts(trip)
        return CoreMaterializationResult(
            trip=trip,
            gps_points=counts.gps_points,
            state_transitions=counts.state_transitions,
            path_points=path_points,
        )
    return CoreMaterializationResult(
        trip=trip,
        gps_points=len(gps_rows),
        state_transitions=len(transition_rows),
        path_points=path_points,
    )


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


def _get_or_create_part_based_trip(ingestion: TripIngestion) -> Trip:
    trip, _ = Trip.objects.get_or_create(
        client_session_id=ingestion.client_session_id,
        defaults={
            "user_id": ingestion.user_id,
            "device_id": ingestion.device_id or "unknown",
            "status": Trip.Status.CLOSED,
        },
    )
    if trip.status == Trip.Status.OPEN:
        trip.status = Trip.Status.CLOSED
    trip.ended_at = ingestion.ended_at or trip.ended_at or timezone.now()
    trip.save(update_fields=["status", "ended_at", "updated_at"])
    return trip


def _part_gps_rows(trip: Trip, ingestion: TripIngestion) -> list[GpsPoint]:
    part = ingestion.parts.filter(
        kind=PartKind.GPS_POINTS,
        received_at__isnull=False,
    ).first()
    if part is None:
        return []

    payload = _load_json_gz(part.object_key)
    rows = []
    for point in payload.get("points", []):
        lat = point.get("latitude")
        lon = point.get("longitude")
        if lat is None or lon is None:
            continue
        rows.append(
            GpsPoint(
                trip=trip,
                timestamp=parse_datetime(point["timestamp"]),
                point=Point(float(lon), float(lat), srid=4326),
                speed_mps=point.get("speed_mps") or 0,
                accuracy_meters=point.get("accuracy_meters"),
            )
        )
    return rows


def _part_transition_rows(
    trip: Trip,
    ingestion: TripIngestion,
) -> list[StateTransition]:
    part = ingestion.parts.filter(
        kind=PartKind.STATE_TRANSITIONS,
        received_at__isnull=False,
    ).first()
    if part is None:
        return []

    payload = _load_json_gz(part.object_key)
    return [
        StateTransition(
            trip=trip,
            from_state=transition["from_state"],
            to_state=transition["to_state"],
            reason=transition.get("reason", ""),
            timestamp=parse_datetime(transition["timestamp"]),
            sigma=transition.get("sigma"),
            speed_mps=transition.get("speed_mps"),
        )
        for transition in payload.get("transitions", [])
    ]


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


def _load_json_gz(object_key: str) -> dict:
    try:
        decompressed = gzip.decompress(storage.read_object(object_key))
        return _load_json_bytes(decompressed)
    except (gzip.BadGzipFile, EOFError) as exc:
        raise InvalidCoreIngestionPayload("payload core gzip non valido") from exc
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise InvalidCoreIngestionPayload("payload core JSON non valido") from exc


def _load_json_bytes(raw: bytes) -> Any:
    if orjson is not None:
        return orjson.loads(raw)
    return json.loads(raw.decode("utf-8"))
