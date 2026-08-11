"""Costruzione del diario privato (preciso) di un Trip.

Prima di questo modulo la stessa proiezione (GPS dell'intervallo, overlay dei
Luoghi Confermati, matching della sosta visibile) era duplicata in due posti:
`mobility.api.get_trip_diary` (superficie mobile) e
`accounts.auth_web.users_api._diary_out` (dashboard web, ramo "precise").
Entrambe le superfici ora chiamano `build_private_diary` e si limitano a
mappare il risultato sul proprio schema di output (regola: un'invariante di
dominio vive in un solo posto).
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

from django.contrib.gis.geos import LineString

from ..diary_projection import project_diary_segments
from ..models import HabitualPlace, MobilitySegment, Trip
from ..selectors.places import confirmed_places_for_user
from ..significant_places import stop_like_source_intervals, visible_stop_summary


@dataclass(frozen=True)
class DiarySegmentPlace:
    matched_place: HabitualPlace | None
    lat: float
    lon: float


@dataclass(frozen=True)
class DiarySegmentView:
    kind: str
    start_timestamp: datetime
    end_timestamp: datetime
    activity_label: str
    distance_meters: float
    path: LineString | None
    place: DiarySegmentPlace | None


def build_private_diary(trip: Trip) -> list[DiarySegmentView]:
    """Diario read-time preciso: soste con la posizione/etichetta dei GPS grezzi."""
    gps = list(trip.gps_points.order_by("timestamp"))
    confirmed = confirmed_places_for_user(trip.user_id)
    persisted_segments = list(trip.segments.all())
    virtual_stop_intervals = list(trip.virtual_stop_intervals.all())
    source_intervals = stop_like_source_intervals(
        persisted_segments,
        virtual_stop_intervals,
    )

    views: list[DiarySegmentView] = []
    for segment in project_diary_segments(persisted_segments, virtual_stop_intervals):
        place = None
        if segment.kind == MobilitySegment.Kind.STOP:
            summary = visible_stop_summary(segment, source_intervals, gps, confirmed)
            if summary is not None:
                place = DiarySegmentPlace(
                    matched_place=summary.matched_place,
                    lat=summary.lat,
                    lon=summary.lon,
                )
        views.append(
            DiarySegmentView(
                kind=segment.kind,
                start_timestamp=segment.start_timestamp,
                end_timestamp=segment.end_timestamp,
                activity_label=segment.activity_label,
                distance_meters=segment.distance_meters,
                path=segment.path,
                place=place,
            )
        )
    return views
