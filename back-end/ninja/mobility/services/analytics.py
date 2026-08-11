"""Business logic delle Analitiche Personali (bucketing, heatmap, percorsi frequenti).

Prima di questo modulo l'intera logica viveva in `mobility.selectors.analytics`
che, oltre alle query, costruiva direttamente le istanze `ninja.Schema`
(`AnalyticsOut` e affini): un selector/repository non deve conoscere il
layer di presentazione (vedi regole shared/repositories). Questo service
ritorna dataclass pure; la mappatura sullo schema Ninja resta nel router
(`mobility.api`), che e' l'unico a importare `mobility.schemas`.
"""

from __future__ import annotations

from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime, time, timedelta
from datetime import timezone as dt_timezone
from zoneinfo import ZoneInfo

from django.utils import timezone

from ..geo import haversine_meters
from ..selectors import analytics as analytics_repository
from ..selectors.places import confirmed_places_for_user
from ..significant_places import place_label

_CATEGORY_BY_ACTIVITY = {
    "IDLE": "fermo",
    "WALKING": "a_piedi",
    "RUNNING": "corsa",
    "BIKING": "in_bici",
    "MOVING_VEHICLE": "in_auto",
}
_MOBILITY_CATEGORIES = ["fermo", "a_piedi", "corsa", "in_bici", "in_auto"]
_ANALYTICS_MAX_SPAN = timedelta(days=3650)


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
    """Analitiche Personali: bucket finestrati + aggregati cumulativi (ADR 0030)."""

    granularity: str
    has_data: bool
    buckets: list[AnalyticsBucket]
    prevalent_mode: str | None
    frequent_routes: list[AnalyticsRoute]
    heatmap: list[AnalyticsHeatPoint]
    weekly_heatmaps: list[AnalyticsWeeklyHeatmap]


def personal_analytics_for_user(
    *,
    user_id: int,
    granularity: str,
    tz: str,
) -> PersonalAnalytics:
    granularity = granularity if granularity in {"day", "week"} else "day"
    zone = _analytics_zone(tz)
    return PersonalAnalytics(
        granularity=granularity,
        has_data=analytics_repository.user_has_trips(user_id),
        buckets=analytics_buckets(user_id, granularity, zone),
        prevalent_mode=prevalent_mode(user_id),
        frequent_routes=frequent_routes(user_id),
        heatmap=analytics_heatmap(user_id),
        weekly_heatmaps=weekly_heatmaps(user_id, zone),
    )


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
        category = _CATEGORY_BY_ACTIVITY.get(row["activity_label"], "fermo")
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


def analytics_heatmap(user_id: int) -> list[AnalyticsHeatPoint]:
    places = confirmed_places_for_user(user_id, only_fields=("center", "visit_count"))
    return [
        AnalyticsHeatPoint(
            lat=place.center.y,
            lon=place.center.x,
            weight=float(place.visit_count),
        )
        for place in places
    ]


def weekly_heatmaps(user_id: int, zone: ZoneInfo) -> list[AnalyticsWeeklyHeatmap]:
    today = timezone.now().astimezone(zone).date()
    anchor = _bucket_start_of(today, "week")
    starts = [anchor - timedelta(weeks=i) for i in range(7, -1, -1)]
    index_by_start = {start: i for i, start in enumerate(starts)}
    trip_ids: list[list[int]] = [[] for _ in starts]
    place_hits = [Counter() for _ in starts]

    places = confirmed_places_for_user(user_id, only_fields=("center", "radius_meters"))
    if not places:
        return []

    by_id = {place.id: place for place in places}
    window_start = datetime.combine(starts[0], time.min, tzinfo=zone)
    trips = analytics_repository.trips_with_path_since(user_id, since=window_start)

    for trip in trips:
        local_date = trip.started_at.astimezone(zone).date()
        index = index_by_start.get(_bucket_start_of(local_date, "week"))
        if index is None:
            continue
        trip_ids[index].append(trip.id)
        coords = trip.path.coords
        if len(coords) < 2:
            continue
        matched = {
            place.id
            for place in (
                _nearest_place(coords[0], places),
                _nearest_place(coords[-1], places),
            )
            if place is not None
        }
        for place_id in matched:
            place_hits[index][place_id] += 1

    return [
        AnalyticsWeeklyHeatmap(
            label=start.strftime("%d/%m"),
            trip_ids=ids,
            habitual_places=[
                AnalyticsHeatPoint(
                    lat=by_id[place_id].center.y,
                    lon=by_id[place_id].center.x,
                    weight=float(weight),
                )
                for place_id, weight in hits.most_common()
            ],
        )
        for start, ids, hits in zip(starts, trip_ids, place_hits)
        if ids or hits
    ]


def prevalent_mode(user_id: int) -> str | None:
    rows = analytics_repository.mobility_segment_activity_rows(user_id)
    totals: dict[str, float] = defaultdict(float)
    for row in rows:
        category = _CATEGORY_BY_ACTIVITY.get(row["activity_label"], "fermo")
        if category == "fermo":
            continue
        totals[category] += (
            row["end_timestamp"] - row["start_timestamp"]
        ).total_seconds()
    return max(totals, key=totals.get) if totals else None


def frequent_routes(user_id: int, limit: int = 5) -> list[AnalyticsRoute]:
    places = confirmed_places_for_user(
        user_id,
        only_fields=("center", "radius_meters", "custom_name", "category"),
    )
    if not places:
        return []

    pairs: Counter = Counter()
    trips = analytics_repository.trips_with_path_since(user_id)
    for trip in trips:
        coords = trip.path.coords
        if len(coords) < 2:
            continue
        origin = _nearest_place(coords[0], places)
        destination = _nearest_place(coords[-1], places)
        if origin is None or destination is None or origin.id == destination.id:
            continue
        pairs[(origin.id, destination.id)] += 1

    by_id = {place.id: place for place in places}
    return [
        AnalyticsRoute(
            origin_label=place_label(by_id[origin_id]),
            destination_label=place_label(by_id[destination_id]),
            trip_count=count,
        )
        for (origin_id, destination_id), count in pairs.most_common(limit)
    ]


def _analytics_zone(tz: str):
    try:
        return dt_timezone(timedelta(minutes=int(tz)))
    except ValueError:
        pass
    try:
        return ZoneInfo(tz)
    except Exception:  # noqa: BLE001
        return ZoneInfo("UTC")


def _bucket_start_of(local_date, granularity: str):
    if granularity == "week":
        return local_date - timedelta(days=local_date.weekday())
    return local_date


def _nearest_place(coord, places):
    lon, lat = coord[0], coord[1]
    best, best_distance = None, None
    for place in places:
        distance = haversine_meters(lat, lon, place.center.y, place.center.x)
        if distance <= max(place.radius_meters or 0, 150.0) and (
            best_distance is None or distance < best_distance
        ):
            best, best_distance = place, distance
    return best
