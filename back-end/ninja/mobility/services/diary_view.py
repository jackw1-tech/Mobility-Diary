"""Costruzione del diario privato
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

from django.contrib.gis.geos import LineString

from ..models import Trip
from ..selectors.places import confirmed_places_for_user
from ..significant_places import VisibleStopSummary, project_diary_with_places


@dataclass(frozen=True)
class DiarySegmentView:
    kind: str
    start_timestamp: datetime
    end_timestamp: datetime
    activity_label: str
    distance_meters: float
    path: LineString | None #In redis conservo direttamente l''oggetto Geo
    place: VisibleStopSummary | None


# Costruzione del diario privato / preciso
def build_private_diary(trip: Trip) -> list[DiarySegmentView]:
    gps = list(trip.gps_points.order_by("timestamp"))
    confirmed = confirmed_places_for_user(trip.user_id)
    persisted_segments = list(trip.segments.all())
    virtual_stop_intervals = list(trip.virtual_stop_intervals.all())

    views: list[DiarySegmentView] = []
    # Due possibili elmenti
    # Segmento Movimento , none
    # Segmento Fermo, nome | abitual pplace
    for segment, summary in project_diary_with_places(
        persisted_segments, virtual_stop_intervals, gps, confirmed
    ):
        views.append(
            DiarySegmentView(
                kind=segment.kind,
                start_timestamp=segment.start_timestamp,
                end_timestamp=segment.end_timestamp,
                activity_label=segment.activity_label,
                distance_meters=segment.distance_meters,
                path=segment.path,
                place=summary,
            )
        )
    return views
