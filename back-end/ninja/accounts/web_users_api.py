import json
from datetime import datetime
from typing import Any

from django.contrib.gis.db.models.functions import AsGeoJSON, Length
from django.contrib.auth import get_user_model
from django.db.models import (
    BooleanField,
    Case,
    Count,
    FloatField,
    Max,
    Q,
    Sum,
    Value,
    When,
)
from django.db.models.functions import Coalesce
from django.utils import timezone
from django.utils.dateparse import parse_datetime
from ninja import Router, Schema
from ninja.errors import HttpError

from .web_auth import web_dashboard_auth
from mobility.models import MobilitySegment, Trip

router = Router(tags=["web-users"])


class WebUserSummaryOut(Schema):
    id: int
    email: str
    first_name: str
    last_name: str
    is_active: bool
    trip_count: int
    processed_trip_count: int
    latest_trip_started_at: datetime | None
    total_distance_meters: float


class WebTripDetailOut(Schema):
    id: int
    started_at: datetime
    ended_at: datetime | None
    status: str
    distance_meters: float | None
    processed: bool


class WebTripListItemOut(WebTripDetailOut):
    has_track: bool


class WebUserTripsOut(Schema):
    owner: WebUserSummaryOut
    trips: list[WebTripListItemOut]


class WebTrackOut(Schema):
    trip_id: int
    point_count: int
    distance_meters: float
    geojson: dict[str, Any] | None


class WebDiarySegmentOut(Schema):
    kind: str
    start_timestamp: datetime
    end_timestamp: datetime
    activity_label: str
    distance_meters: float
    path_geojson: dict[str, Any] | None = None


class WebDiaryOut(Schema):
    trip_id: int
    status: str
    processed: bool
    segments: list[WebDiarySegmentOut]


class WebTripDashboardOut(Schema):
    owner: WebUserSummaryOut
    trip: WebTripDetailOut
    track: WebTrackOut
    diary: WebDiaryOut


def _web_users_queryset():
    return (
        get_user_model()
        ._default_manager.filter(is_staff=False, is_superuser=False)
        .annotate(
            trip_count=Count("trips", distinct=True),
            processed_trip_count=Count(
                "trips",
                filter=Q(trips__status=Trip.Status.PROCESSED),
                distinct=True,
            ),
            latest_trip_started_at=Max("trips__started_at"),
            total_distance_meters=Coalesce(
                Sum("trips__distance_meters"),
                Value(0.0),
                output_field=FloatField(),
            ),
        )
    )


def _web_user_summary_values(queryset):
    return queryset.values(
        "id",
        "email",
        "first_name",
        "last_name",
        "is_active",
        "trip_count",
        "processed_trip_count",
        "latest_trip_started_at",
        "total_distance_meters",
    )


def _parse_datetime_filter(params, name: str) -> datetime | None:
    raw_value = params.get(name)
    if not raw_value:
        return None

    value = parse_datetime(raw_value)
    if value is None:
        raise HttpError(400, f"Filtro {name} non valido")
    return timezone.make_aware(value) if timezone.is_naive(value) else value


def _parse_bool_filter(params, name: str) -> bool | None:
    raw_value = params.get(name)
    if not raw_value:
        return None
    normalized = raw_value.lower()
    if normalized in {"true", "1", "yes"}:
        return True
    if normalized in {"false", "0", "no"}:
        return False
    raise HttpError(400, f"Filtro {name} non valido")


def _filter_web_trips(queryset, params):
    started_from = _parse_datetime_filter(params, "from")
    started_to = _parse_datetime_filter(params, "to")
    status = params.get("status")
    processed = _parse_bool_filter(params, "processed")
    has_track = _parse_bool_filter(params, "has_track")

    if started_from:
        queryset = queryset.filter(started_at__gte=started_from)
    if started_to:
        queryset = queryset.filter(started_at__lte=started_to)
    if status:
        if status not in Trip.Status.values:
            raise HttpError(400, "Filtro status non valido")
        queryset = queryset.filter(status=status)
    if processed is not None:
        queryset = (
            queryset.filter(status=Trip.Status.PROCESSED)
            if processed
            else queryset.exclude(status=Trip.Status.PROCESSED)
        )
    if has_track is not None:
        queryset = queryset.filter(path__isnull=not has_track)
    return queryset


def _web_trip_values(queryset):
    return queryset.annotate(
        processed=Case(
            When(status=Trip.Status.PROCESSED, then=Value(True)),
            default=Value(False),
            output_field=BooleanField(),
        ),
        has_track=Case(
            When(path__isnull=False, then=Value(True)),
            default=Value(False),
            output_field=BooleanField(),
        ),
    ).order_by("-started_at", "-id").values(
        "id",
        "started_at",
        "ended_at",
        "status",
        "distance_meters",
        "processed",
        "has_track",
    )


def _track_out(trip: Trip) -> WebTrackOut:
    row = (
        Trip.objects.filter(pk=trip.pk)
        .annotate(
            track_geojson=AsGeoJSON("path"),
            track_distance=Length("path"),
            point_count=Count("gps_points"),
        )
        .values("id", "track_geojson", "track_distance", "point_count")
        .get()
    )
    distance = row["track_distance"]
    return WebTrackOut(
        trip_id=row["id"],
        point_count=row["point_count"],
        distance_meters=float(distance.m if hasattr(distance, "m") else distance or 0),
        geojson=json.loads(row["track_geojson"]) if row["track_geojson"] else None,
    )


def _diary_out(trip: Trip) -> WebDiaryOut:
    return WebDiaryOut(
        trip_id=trip.id,
        status=trip.status,
        processed=trip.status == Trip.Status.PROCESSED,
        segments=[
            WebDiarySegmentOut(
                kind=segment.kind,
                start_timestamp=segment.start_timestamp,
                end_timestamp=segment.end_timestamp,
                activity_label=segment.activity_label,
                distance_meters=segment.distance_meters,
                path_geojson=json.loads(segment.path.geojson)
                if segment.kind == MobilitySegment.Kind.MOVE and segment.path is not None
                else None,
            )
            for segment in trip.segments.all()
        ],
    )


@router.get("/users", response=list[WebUserSummaryOut], auth=web_dashboard_auth)
def list_web_users(request):
    return list(_web_user_summary_values(_web_users_queryset().order_by("email")))


@router.get("/users/{user_id}/trips", response=WebUserTripsOut, auth=web_dashboard_auth)
def list_web_user_trips(request, user_id: int):
    owner = _web_user_summary_values(_web_users_queryset().filter(id=user_id)).first()
    if owner is None:
        raise HttpError(404, "Proprietario del Viaggio non trovato")

    trips = _filter_web_trips(Trip.objects.filter(user_id=user_id), request.GET)

    return {
        "owner": owner,
        "trips": list(_web_trip_values(trips)),
    }


@router.get(
    "/users/{user_id}/trips/{trip_id}",
    response=WebTripDashboardOut,
    auth=web_dashboard_auth,
)
def get_web_trip_dashboard(request, user_id: int, trip_id: int):
    owner = _web_user_summary_values(_web_users_queryset().filter(id=user_id)).first()
    trip = Trip.objects.filter(id=trip_id, user_id=user_id).first()
    if owner is None or trip is None:
        raise HttpError(404, "Viaggio non trovato")

    return {
        "owner": owner,
        "trip": WebTripDetailOut(
            id=trip.id,
            started_at=trip.started_at,
            ended_at=trip.ended_at,
            status=trip.status,
            distance_meters=trip.distance_meters,
            processed=trip.status == Trip.Status.PROCESSED,
        ),
        "track": _track_out(trip),
        "diary": _diary_out(trip),
    }
