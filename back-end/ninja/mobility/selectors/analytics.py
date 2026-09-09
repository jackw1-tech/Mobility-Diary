"""Repository delle Analitiche Personali.
"""

from __future__ import annotations

from datetime import datetime
from typing import Any

from django.db.models import Max, Min

from ..models import MobilitySegment, Trip


def user_has_trips(user_id: int) -> bool:
    return Trip.objects.filter(user_id=user_id).exists()


def mobility_segment_time_span(user_id: int) -> dict[str, datetime | None]:
    return MobilitySegment.objects.filter(trip__user_id=user_id).aggregate(
        first=Min("start_timestamp"),
        last=Max("start_timestamp"),
    )


def mobility_segment_rows_from(user_id: int, *, since: datetime) -> list[dict[str, Any]]:
    return list(
        MobilitySegment.objects.filter(
            trip__user_id=user_id,
            start_timestamp__gte=since,
        ).values("start_timestamp", "end_timestamp", "activity_label", "distance_meters")
    )


def mobility_segment_activity_rows(user_id: int) -> list[dict[str, Any]]:
    return list(
        MobilitySegment.objects.filter(trip__user_id=user_id).values(
            "activity_label",
            "start_timestamp",
            "end_timestamp",
        )
    )


def trips_with_path_since(user_id: int, *, since: datetime | None = None):
    queryset = Trip.objects.filter(user_id=user_id, path__isnull=False)
    if since is not None:
        queryset = queryset.filter(started_at__gte=since)
    return list(queryset.only("id", "started_at", "path").order_by("started_at"))
