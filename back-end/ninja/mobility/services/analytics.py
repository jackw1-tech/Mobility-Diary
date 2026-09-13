"""Analitiche Personali
"""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass
from datetime import datetime, time, timedelta
from zoneinfo import ZoneInfo

from ..models import ActivityLabel
from ..selectors import analytics as analytics_repository
from ..significant_places import NEUTRAL_PLACE_LABEL

_MOBILITY_CATEGORIES = tuple(ActivityLabel.values)
_ANALYTICS_MAX_SPAN = timedelta(days=3650)
_ANALYTICS_ZONE = ZoneInfo("Europe/Rome")


@dataclass(frozen=True)
class AnalyticsCategorySlice:
    category: str
    seconds: float
    distance_meters: float


@dataclass(frozen=True)
class AnalyticsBucket:
    label: str
    categories: list[AnalyticsCategorySlice]


@dataclass(frozen=True)
class AnalyticsRoute:
    origin_label: str
    destination_label: str
    trip_count: int


@dataclass(frozen=True)
class AnalyticsHeatPoint:
    lat: float
    lon: float
    weight: float


@dataclass(frozen=True)
class AnalyticsWeeklyHeatmap:
    label: str
    trip_ids: list[int]
    habitual_places: list[AnalyticsHeatPoint]


@dataclass(frozen=True)
class PersonalAnalytics:
    granularity: str
    has_data: bool
    buckets: list[AnalyticsBucket]
    prevalent_mode: str | None
    frequent_routes: list[AnalyticsRoute]
    weekly_heatmaps: list[AnalyticsWeeklyHeatmap]


def personal_analytics_for_user(
    *,
    user_id: int,
    granularity: str,
) -> PersonalAnalytics:
    granularity = granularity if granularity in {"day", "week"} else "day"
    return PersonalAnalytics(
        granularity=granularity,
        has_data=analytics_repository.user_has_trips(user_id),
        buckets=analytics_buckets(user_id, granularity, _ANALYTICS_ZONE),
        prevalent_mode=prevalent_mode(user_id),
        frequent_routes=frequent_routes(user_id),
        weekly_heatmaps=(
            weekly_heatmaps(user_id, _ANALYTICS_ZONE)
            if granularity == "week"
            else []
        ),
    )

#Barre delle statistiche front end client
def analytics_buckets(
    user_id: int, granularity: str, zone: ZoneInfo
) -> list[AnalyticsBucket]:
    step = timedelta(weeks=1) if granularity == "week" else timedelta(days=1)

    span = analytics_repository.mobility_segment_time_span(user_id)
    if span["first"] is None:
        return []

    first_start = _bucket_start_of(span["first"].astimezone(zone).date(), granularity)
    last_start = _bucket_start_of(span["last"].astimezone(zone).date(), granularity)
    earliest_allowed = _bucket_start_of(last_start - _ANALYTICS_MAX_SPAN, granularity)
    if first_start < earliest_allowed:
        first_start = earliest_allowed

    starts = []
    cursor = first_start
    while cursor <= last_start:
        starts.append(cursor)
        cursor += step

    index_by_start = {start: i for i, start in enumerate(starts)}
    totals = [{c: [0.0, 0.0] for c in _MOBILITY_CATEGORIES} for _ in starts]

    window_start = datetime.combine(starts[0], time.min, tzinfo=zone)
    rows = analytics_repository.mobility_segment_rows_from(user_id, since=window_start)

    for row in rows:
        local_date = row["start_timestamp"].astimezone(zone).date()
        index = index_by_start.get(_bucket_start_of(local_date, granularity))
        if index is None:
            continue
        category = row["activity_label"]
        if category not in _MOBILITY_CATEGORIES:
            continue
        seconds = (row["end_timestamp"] - row["start_timestamp"]).total_seconds()
        cell = totals[index][category]
        cell[0] += max(0.0, seconds)
        cell[1] += float(row["distance_meters"] or 0)

    return [
        AnalyticsBucket(
            label=start.strftime("%d/%m/%y"),
            categories=[
                AnalyticsCategorySlice(
                    category=category,
                    seconds=cell[category][0],
                    distance_meters=cell[category][1],
                )
                for category in _MOBILITY_CATEGORIES
            ],
        )
        for start, cell in zip(starts, totals)
    ]


def weekly_heatmaps(user_id: int, zone: ZoneInfo) -> list[AnalyticsWeeklyHeatmap]:
    return [
        AnalyticsWeeklyHeatmap(
            label=row["week_start"].strftime("%d/%m/%y"),
            trip_ids=row["trip_ids"],
            habitual_places=[
                AnalyticsHeatPoint(
                    lat=point["lat"],
                    lon=point["lon"],
                    weight=point["weight"],
                )
                for point in row["habitual_places"]
            ],
        )
        for row in analytics_repository.weekly_heatmap_rows(
            user_id,
            timezone_name=zone.key,
        )
    ]

#Somma di tutti i segmenti storici , tolto IDLE -> restituisce il più frequente
def prevalent_mode(user_id: int) -> str | None:
    rows = analytics_repository.mobility_segment_activity_rows(user_id)
    totals: dict[str, float] = defaultdict(float)
    for row in rows:
        category = row["activity_label"]
        if category == ActivityLabel.IDLE or category not in _MOBILITY_CATEGORIES:
            continue
        totals[category] += (
            row["end_timestamp"] - row["start_timestamp"]
        ).total_seconds()
    return max(totals, key=totals.get) if totals else None

#Trova i percorsi più frequenti tra i luoghi abituali confermati.
def frequent_routes(user_id: int, limit: int = 5) -> list[AnalyticsRoute]:
    return [
        AnalyticsRoute(
            origin_label=row["origin_custom_name"]
            or row["origin_category"]
            or NEUTRAL_PLACE_LABEL,
            destination_label=row["destination_custom_name"]
            or row["destination_category"]
            or NEUTRAL_PLACE_LABEL,
            trip_count=row["trip_count"],
        )
        for row in analytics_repository.frequent_route_rows(user_id, limit=limit)
    ]


"Determina la data iniziale del bucket in cui inserire un segmento"
def _bucket_start_of(local_date, granularity: str):
    if granularity == "week":
        return local_date - timedelta(days=local_date.weekday())
    return local_date
