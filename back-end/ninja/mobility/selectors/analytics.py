"""Repository delle Analitiche Personali.
"""

from __future__ import annotations

import json
from datetime import datetime
from typing import Any

from django.db import connection
from django.db.models import Max, Min

from ..models import HabitualPlace, MobilitySegment, Trip


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

#Trova le rotte più frequentate dell'utente
def frequent_route_rows(user_id: int, *, limit: int = 5) -> list[dict[str, Any]]:
    if limit <= 0:
        return []

    trip_table = connection.ops.quote_name(Trip._meta.db_table)
    place_table = connection.ops.quote_name(HabitualPlace._meta.db_table)
    with connection.cursor() as cursor:
        cursor.execute(
            f"""
            SELECT
                origin.custom_name AS origin_custom_name,
                origin.category AS origin_category,
                destination.custom_name AS destination_custom_name,
                destination.category AS destination_category,
                COUNT(*)::integer AS trip_count
            FROM {trip_table} AS trip
            CROSS JOIN LATERAL (
                SELECT
                    ST_StartPoint(trip.path::geometry)::geography AS origin,
                    ST_EndPoint(trip.path::geometry)::geography AS destination
            ) AS endpoints
            JOIN LATERAL (
                SELECT place.id, place.custom_name, place.category
                FROM {place_table} AS place
                WHERE place.user_id = trip.user_id
                  AND place.state = 'CONFIRMED'
                  AND ST_DWithin(
                      place.center,
                      endpoints.origin,
                      GREATEST(place.radius_meters, %s)
                  )
                ORDER BY ST_Distance(place.center, endpoints.origin), place.id
                LIMIT 1
            ) AS origin ON TRUE
            JOIN LATERAL (
                SELECT place.id, place.custom_name, place.category
                FROM {place_table} AS place
                WHERE place.user_id = trip.user_id
                  AND place.state = 'CONFIRMED'
                  AND ST_DWithin(
                      place.center,
                      endpoints.destination,
                      GREATEST(place.radius_meters, %s)
                  )
                ORDER BY ST_Distance(place.center, endpoints.destination), place.id
                LIMIT 1
            ) AS destination ON TRUE
            WHERE trip.user_id = %s
              AND trip.path IS NOT NULL
              AND ST_NPoints(trip.path::geometry) >= 2
              AND origin.id <> destination.id
            GROUP BY
                origin.id,
                origin.custom_name,
                origin.category,
                destination.id,
                destination.custom_name,
                destination.category
            ORDER BY trip_count DESC, origin.id, destination.id
            LIMIT %s
            """,
            [150.0, 150.0, user_id, limit],
        )
        columns = [column.name for column in cursor.description]
        return [dict(zip(columns, row)) for row in cursor.fetchall()]


def weekly_heatmap_rows(
    user_id: int,
    *,
    timezone_name: str,
) -> list[dict[str, Any]]:
    trip_table = connection.ops.quote_name(Trip._meta.db_table)
    place_table = connection.ops.quote_name(HabitualPlace._meta.db_table)
    with connection.cursor() as cursor:
        cursor.execute(
            f"""
            WITH trips AS (
                SELECT
                    trip.id,
                    trip.user_id,
                    DATE_TRUNC(
                        'week',
                        trip.started_at AT TIME ZONE %s
                    )::date AS week_start,
                    trip.path
                FROM {trip_table} AS trip
                WHERE trip.user_id = %s
            ),
            trip_endpoints AS (
                SELECT
                    trip.id,
                    trip.user_id,
                    trip.week_start,
                    ST_StartPoint(trip.path::geometry)::geography AS origin,
                    ST_EndPoint(trip.path::geometry)::geography AS destination
                FROM trips AS trip
                WHERE trip.path IS NOT NULL
                  AND ST_NPoints(trip.path::geometry) >= 2
            ),
            trip_places AS (
                SELECT trip.id AS trip_id, trip.week_start, origin.id AS place_id
                FROM trip_endpoints AS trip
                JOIN LATERAL (
                    SELECT place.id
                    FROM {place_table} AS place
                    WHERE place.user_id = trip.user_id
                      AND place.state = 'CONFIRMED'
                      AND ST_DWithin(
                          place.center,
                          trip.origin,
                          GREATEST(place.radius_meters, %s)
                      )
                    ORDER BY ST_Distance(place.center, trip.origin), place.id
                    LIMIT 1
                ) AS origin ON TRUE

                UNION

                SELECT trip.id AS trip_id, trip.week_start, destination.id AS place_id
                FROM trip_endpoints AS trip
                JOIN LATERAL (
                    SELECT place.id
                    FROM {place_table} AS place
                    WHERE place.user_id = trip.user_id
                      AND place.state = 'CONFIRMED'
                      AND ST_DWithin(
                          place.center,
                          trip.destination,
                          GREATEST(place.radius_meters, %s)
                      )
                    ORDER BY ST_Distance(place.center, trip.destination), place.id
                    LIMIT 1
                ) AS destination ON TRUE
            ),
            trip_weeks AS (
                SELECT
                    week_start,
                    ARRAY_AGG(id ORDER BY id) AS trip_ids
                FROM trips
                GROUP BY week_start
            ),
            place_counts AS (
                SELECT
                    trip_place.week_start,
                    place.id,
                    ST_Y(place.center::geometry) AS lat,
                    ST_X(place.center::geometry) AS lon,
                    COUNT(*)::double precision AS weight
                FROM trip_places AS trip_place
                JOIN {place_table} AS place ON place.id = trip_place.place_id
                GROUP BY trip_place.week_start, place.id
            )
            SELECT
                trip_week.week_start,
                trip_week.trip_ids,
                COALESCE(
                    JSONB_AGG(
                        JSONB_BUILD_OBJECT(
                            'lat', place_count.lat,
                            'lon', place_count.lon,
                            'weight', place_count.weight
                        )
                        ORDER BY place_count.weight DESC, place_count.id
                    ) FILTER (WHERE place_count.id IS NOT NULL),
                    '[]'::jsonb
                ) AS habitual_places
            FROM trip_weeks AS trip_week
            LEFT JOIN place_counts AS place_count
                ON place_count.week_start = trip_week.week_start
            GROUP BY trip_week.week_start, trip_week.trip_ids
            ORDER BY trip_week.week_start
            """,
            [timezone_name, user_id, 150.0, 150.0],
        )
        columns = [column.name for column in cursor.description]
        rows = [dict(zip(columns, row)) for row in cursor.fetchall()]
        for row in rows:
            if isinstance(row["habitual_places"], str):
                row["habitual_places"] = json.loads(row["habitual_places"])
        return rows
