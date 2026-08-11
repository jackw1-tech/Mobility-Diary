"""Repository di MobilitySegment e VirtualStopInterval.

Unico punto in cui compaiono `MobilitySegment.objects` e
`VirtualStopInterval.objects` (le letture per-trip passano dal related
manager di un'istanza Trip gia' caricata, es. `trip.segments.all()`, che non
e' `Model.objects` e resta quindi nel chiamante).
"""

from __future__ import annotations

from datetime import datetime

from django.contrib.gis.geos import LineString

from ..models import ActivityLabel, MobilitySegment, Trip, VirtualStopInterval


def create_stop_segment(trip: Trip, start: datetime, end: datetime) -> MobilitySegment:
    return MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.STOP,
        start_timestamp=start,
        end_timestamp=end,
        activity_label=ActivityLabel.IDLE,
        path=None,
    )


def create_move_segment(
    trip: Trip,
    *,
    start: datetime,
    end: datetime,
    label: str,
    path: LineString | None,
    distance_meters: float,
) -> MobilitySegment:
    return MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.MOVE,
        start_timestamp=start,
        end_timestamp=end,
        activity_label=label,
        path=path,
        distance_meters=distance_meters,
    )


def create_virtual_stop(trip: Trip, start: datetime, end: datetime) -> VirtualStopInterval:
    return VirtualStopInterval.objects.create(
        trip=trip,
        start_timestamp=start,
        end_timestamp=end,
    )
