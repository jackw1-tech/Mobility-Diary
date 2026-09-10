"""Business logic della dashboard web (superficie staff): track, diario e
vista privacy-aware di un Trip.

Prima dell'introduzione di questo modulo, l'intera costruzione della vista
(query GPS/Luoghi Confermati, overlay delle soste, approssimazione spaziale) era
duplicata dentro `accounts.auth_web.users_api`, che reimplementava a mano una
buona parte di cio' che questo context espone gia' altrove
(`mobility.diary_export`, `mobility.diary_projection`,
`mobility.services.diary_view`, `mobility.privacy`,
`mobility.significant_places`). Il router web ora chiama solo queste funzioni
e mappa il risultato sul proprio schema Ninja.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from django.contrib.gis.geos import Point

from accounts import repositories as accounts_repositories
from accounts.models import UserPrivacySettings
from shared.exceptions import ServiceError

from ..diary_export import build_trip_privacy_export
from ..models import MobilitySegment, Trip
from ..privacy import (
    PRIVACY_AWARE_STOP_LABEL,
    PrivacyMetrics,
    approximate_linestring,
    approximate_point,
    line_geojson,
    point_geojson,
    privacy_metrics as compute_privacy_metrics,
)
from ..selectors import trips as trips_repository
from ..selectors.sensor_readings import (
    MOTION_AXES,
    find_motion_stats_by_activity,
    find_sensor_gaps,
)
from ..significant_places import VisibleStopDetails, place_label
from .diary_view import build_private_diary

SENSOR_GAP_THRESHOLD_MS = 10


class DashboardServiceError(ServiceError):
    status_code = 400


class InvalidPrivacyLevel(DashboardServiceError):
    status_code = 400


@dataclass(frozen=True)
class TrackView:
    trip_id: int
    point_count: int
    distance_meters: float
    geojson: dict[str, Any] | None


@dataclass(frozen=True)
class DiarySegmentPlaceView:
    center_geojson: dict[str, Any] | None
    label: str
    radius_meters: float


@dataclass(frozen=True)
class DiarySegmentRowView:
    kind: str
    start_timestamp: datetime
    end_timestamp: datetime
    activity_label: str
    distance_meters: float
    path_geojson: dict[str, Any] | None
    place: DiarySegmentPlaceView | None


@dataclass(frozen=True)
class DiaryView:
    trip_id: int
    status: str
    processed: bool
    segments: list[DiarySegmentRowView]


@dataclass(frozen=True)
class SignificantPlaceView:
    center_geojson: dict[str, Any] | None
    label: str
    radius_meters: float
    dwell_seconds: int


@dataclass(frozen=True)
class SensorGapView:
    start_timestamp: datetime
    end_timestamp: datetime
    gap_seconds: float


@dataclass(frozen=True)
class AxisStatsView:
    mean: float
    std: float


@dataclass(frozen=True)
class MotionStatsView:
    activity_label: str
    sample_count: int
    axes: dict[str, AxisStatsView]


@dataclass(frozen=True)
class PrivacyAwareView:
    level: str
    default_level: str
    track: TrackView
    diary: DiaryView
    significant_places: list[SignificantPlaceView]
    metrics: PrivacyMetrics

def track_view(trip: Trip) -> TrackView:
    track = trips_repository.trip_track_for_user(trip.id, trip.user_id)
    return TrackView(
        trip_id=track["trip_id"],
        point_count=track["point_count"],
        distance_meters=track["distance_meters"],
        geojson=track["geojson"],
    )


def sensor_gaps_view(trip: Trip) -> list[SensorGapView]:
    rows = find_sensor_gaps(trip.id, threshold_ms=SENSOR_GAP_THRESHOLD_MS)
    return [
        SensorGapView(
            start_timestamp=start,
            end_timestamp=end,
            gap_seconds=gap.total_seconds(),
        )
        for start, end, gap in rows
    ]


def motion_stats_by_activity(user_id: int) -> list[MotionStatsView]:
    rows = find_motion_stats_by_activity(user_id)
    return [
        MotionStatsView(
            activity_label=row["activity_label"],
            sample_count=row["sample_count"],
            axes={
                axis: AxisStatsView(
                    mean=row[f"{axis}_mean"] or 0.0,
                    std=row[f"{axis}_std"] or 0.0,
                )
                for axis in MOTION_AXES
            },
        )
        for row in rows
    ]

# Costruisce la traccia in base al livello privacy selezionato.
def privacy_track_view(trip: Trip, *, level: str) -> TrackView:
    approximated_line = approximate_linestring(trip.path, level=level)
    return TrackView(
        trip_id=trip.id,
        point_count=(
            approximated_line.geometry.num_coords
            if approximated_line is not None
            else 0
        ),
        distance_meters=(
            approximated_line.distance_meters if approximated_line is not None else 0
        ),
        geojson=line_geojson(approximated_line),
    )


def _segment_place_view(
    segment_place: VisibleStopDetails | None,
    *,
    level: str | None,
) -> DiarySegmentPlaceView | None:
    if segment_place is None:
        return None
    masked = level not in (None, UserPrivacySettings.Level.PRECISE)
    place = segment_place.matched_place
    if masked:
        coordinate = approximate_point(
            Point(segment_place.lon, segment_place.lat, srid=4326),
            level=level,
        )
    else:
        coordinate = (segment_place.lon, segment_place.lat)
    return DiarySegmentPlaceView(
        center_geojson=point_geojson(coordinate),
        label=(
            PRIVACY_AWARE_STOP_LABEL
            if masked
            else place_label(place) if place is not None else "Sosta rilevata"
        ),
        radius_meters=0 if place is None else place.radius_meters,
    )


def _private_diary_view(
    trip: Trip, precise_segments: list | None = None
) -> DiaryView:
    diary_segments = (
        build_private_diary(trip) if precise_segments is None else precise_segments
    )
    segments = [
        DiarySegmentRowView(
            kind=segment.kind,
            start_timestamp=segment.start_timestamp,
            end_timestamp=segment.end_timestamp,
            activity_label=segment.activity_label,
            distance_meters=segment.distance_meters,
            path_geojson=(
                None if segment.path is None else json.loads(segment.path.geojson)
            ),
            place=_segment_place_view(segment.place, level=None),
        )
        for segment in diary_segments
    ]
    return DiaryView(
        trip_id=trip.id,
        status=trip.status,
        processed=trip.status == Trip.Status.PROCESSED,
        segments=segments,
    )


def _export_segment_path_geojson(segment) -> dict[str, Any] | None:
    if segment.kind != MobilitySegment.Kind.MOVE or not segment.coordinates:
        return None
    return {"type": "LineString", "coordinates": segment.coordinates}


def _export_segment_place_view(segment, *, level: str) -> DiarySegmentPlaceView | None:
    if segment.kind != MobilitySegment.Kind.STOP:
        return None
    if level == UserPrivacySettings.Level.AGGREGATED:
        return None
    return DiarySegmentPlaceView(center_geojson=None, label=segment.title, radius_meters=0)


# export diario con livello di privacy impostato
def _privacy_diary_view_from_export(trip: Trip, *, level: str) -> DiaryView:
    export = build_trip_privacy_export(trip, level=level)
    return DiaryView(
        trip_id=trip.id,
        status=trip.status,
        processed=trip.status == Trip.Status.PROCESSED,
        segments=[
            DiarySegmentRowView(
                kind=segment.kind,
                start_timestamp=segment.start_timestamp,
                end_timestamp=segment.end_timestamp,
                activity_label=segment.activity_label,
                distance_meters=segment.distance_meters,
                path_geojson=_export_segment_path_geojson(segment),
                place=_export_segment_place_view(segment, level=level),
            )
            for segment in export.segments
        ],
    )


#Controlla il livello di privacy e costruisce il diario
def diary_view(
    trip: Trip, *, level: str | None = None, precise_segments: list | None = None
) -> DiaryView:
    if level is not None:
        return _privacy_diary_view_from_export(trip, level=level)
    return _private_diary_view(trip, precise_segments)


def significant_places_view(
    trip: Trip, *, level: str, precise_segments: list | None = None
) -> list[SignificantPlaceView]:
    # Solo aggregated maschera anche il nome del luogo (coerente con
    # _segment_title in diary_export.py): approximate lo mostra reale, la
    # privacy sulla posizione la fa gia' il cloaking spaziale delle coordinate.
    masked = level == UserPrivacySettings.Level.AGGREGATED
    diary_segments = (
        build_private_diary(trip) if precise_segments is None else precise_segments
    )
    aggregated: dict[int, dict[str, Any]] = {}
    for segment in diary_segments:
        if segment.place is None or segment.place.matched_place is None:
            continue
        place = segment.place.matched_place
        bucket = aggregated.setdefault(place.id, {"place": place, "dwell_seconds": 0})
        bucket["dwell_seconds"] += int(
            (segment.end_timestamp - segment.start_timestamp).total_seconds()
        )
    return [
        SignificantPlaceView(
            center_geojson=point_geojson(
                approximate_point(item["place"].center, level=level)
            ),
            label=PRIVACY_AWARE_STOP_LABEL if masked else place_label(item["place"]),
            radius_meters=item["place"].radius_meters,
            dwell_seconds=item["dwell_seconds"],
        )
        for item in aggregated.values()
    ]




#Funzione che fa partire la costruzione del diario per dashboard admin
def privacy_aware_view(
    trip: Trip, *, requested_level: str | None, precise_segments: list | None = None
) -> PrivacyAwareView:
    default_level = accounts_repositories.get_or_create_privacy_settings(
        trip.user_id
    ).level
    level = default_level if requested_level is None else requested_level
    if level not in UserPrivacySettings.Level.values:
        raise InvalidPrivacyLevel("Livello privacy non valido")
    if precise_segments is None:
        precise_segments = build_private_diary(trip)

    protected = level != UserPrivacySettings.Level.PRECISE
    return PrivacyAwareView(
        level=level,
        default_level=default_level,
        track=(
            privacy_track_view(trip, level=level) if protected else track_view(trip)
        ),
        diary=diary_view(
            trip,
            level=level if protected else None,
            precise_segments=precise_segments,
        ),
        significant_places=significant_places_view(
            trip, level=level, precise_segments=precise_segments
        ),
        metrics=compute_privacy_metrics(trip.path, level=level),
    )
