"""Business logic della dashboard web (superficie staff): track, diario e
vista privacy-aware di un Trip.

Prima dell'introduzione di questo modulo, l'intera costruzione della vista
(query GPS/Luoghi Confermati, overlay delle soste, cloaking privacy) era
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
    cloak_linestring,
    cloak_point,
    line_geojson,
    point_geojson,
    privacy_metrics as compute_privacy_metrics,
)
from ..selectors import trips as trips_repository
from ..significant_places import VisibleStopSummary, place_label
from .diary_view import build_private_diary


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
class PrivacyAwareView:
    level: str
    default_level: str
    track: TrackView
    diary: DiaryView
    significant_places: list[SignificantPlaceView]
    metrics: PrivacyMetrics


def saved_privacy_level(trip: Trip) -> str:
    settings = accounts_repositories.get_or_create_privacy_settings(trip.user_id)
    return settings.level


def resolve_privacy_level(trip: Trip, requested: str | None) -> str:
    """Sceglie il livello per una vista privacy-aware senza toccare quello salvato.

    Nessuna query param significa "usa la Preferenza Privacy salvata
    dall'utente"; un livello esplicito e' accettato solo dopo validazione,
    cosi' un Operatore Web puo' confrontare i livelli senza mutare la
    preferenza dell'utente.
    """
    if requested is None:
        return saved_privacy_level(trip)
    if requested not in UserPrivacySettings.Level.values:
        raise InvalidPrivacyLevel("Livello privacy non valido")
    return requested


def track_view(trip: Trip) -> TrackView:
    track = trips_repository.trip_track_for_user(trip.id, trip.user_id)
    return TrackView(**track)


def privacy_track_view(trip: Trip, *, level: str) -> TrackView:
    cloaked_line = cloak_linestring(trip.path, level=level)
    return TrackView(
        trip_id=trip.id,
        point_count=cloaked_line.point_count if cloaked_line is not None else 0,
        distance_meters=cloaked_line.distance_meters if cloaked_line is not None else 0,
        geojson=line_geojson(cloaked_line),
    )


def _segment_place_view(
    segment_place: VisibleStopSummary | None,
    *,
    level: str | None,
) -> DiarySegmentPlaceView | None:
    if segment_place is None:
        return None
    masked = level not in (None, UserPrivacySettings.Level.PRECISE)
    place = segment_place.matched_place
    if masked:
        coordinate = cloak_point(
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


def _private_diary_view(trip: Trip) -> DiaryView:
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
        for segment in build_private_diary(trip)
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


def diary_view(trip: Trip, *, level: str | None = None) -> DiaryView:
    if level is not None:
        return _privacy_diary_view_from_export(trip, level=level)
    return _private_diary_view(trip)


def significant_places_view(trip: Trip, *, level: str) -> list[SignificantPlaceView]:
    """Luoghi Confermati toccati dal viaggio, con il tempo di sosta cumulato.

    Riusa `build_private_diary`, che ha gia' calcolato il match sosta -> Luogo
    Confermato: prima questa funzione ripeteva da capo la stessa query
    (GPS, Luoghi Confermati, intervalli sosta) gia' fatta per il diario.
    """
    masked = level != UserPrivacySettings.Level.PRECISE
    aggregated: dict[int, dict[str, Any]] = {}
    for segment in build_private_diary(trip):
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
                cloak_point(item["place"].center, level=level)
            ),
            label=PRIVACY_AWARE_STOP_LABEL if masked else place_label(item["place"]),
            radius_meters=item["place"].radius_meters,
            dwell_seconds=item["dwell_seconds"],
        )
        for item in aggregated.values()
    ]


def privacy_metrics_view(trip: Trip, *, level: str) -> PrivacyMetrics:
    return compute_privacy_metrics(trip.path, level=level)


def privacy_aware_view(trip: Trip, *, requested_level: str | None) -> PrivacyAwareView:
    default_level = saved_privacy_level(trip)
    level = resolve_privacy_level(trip, requested_level)
    precise = level == UserPrivacySettings.Level.PRECISE
    return PrivacyAwareView(
        level=level,
        default_level=default_level,
        track=track_view(trip) if precise else privacy_track_view(trip, level=level),
        diary=diary_view(trip, level=None if precise else level),
        significant_places=significant_places_view(trip, level=level),
        metrics=privacy_metrics_view(trip, level=level),
    )
