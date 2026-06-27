import json
from datetime import datetime
from typing import Any

from django.contrib.gis.db.models.functions import AsGeoJSON, Length
from django.contrib.gis.geos import Point
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
from .models import UserPrivacySettings
from mobility.diary_projection import project_trip_diary_segments
from mobility.models import HabitualPlace, MobilitySegment, Trip
from mobility.privacy import (
    PRIVACY_AWARE_STOP_LABEL,
    cloak_linestring,
    cloak_point,
    line_geojson,
    point_geojson,
    privacy_metrics,
)
from mobility.significant_places import (
    place_label,
    stop_like_source_intervals,
    visible_stop_place,
    visible_stop_summary,
)

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


class WebDiaryPlaceOut(Schema):
    center_geojson: dict[str, Any] | None
    label: str
    radius_meters: float


class WebDiarySegmentOut(Schema):
    kind: str
    start_timestamp: datetime
    end_timestamp: datetime
    activity_label: str
    distance_meters: float
    path_geojson: dict[str, Any] | None = None
    place: WebDiaryPlaceOut | None = None


class WebDiaryOut(Schema):
    trip_id: int
    status: str
    processed: bool
    segments: list[WebDiarySegmentOut]


class WebSignificantPlaceOut(Schema):
    center_geojson: dict[str, Any] | None
    label: str
    radius_meters: float
    dwell_seconds: int


class WebPrivacyPerturbationOut(Schema):
    mean_meters: float
    max_meters: float
    sample_count: int


class WebQualityOfServiceOut(Schema):
    relative_distance_error: float
    private_distance_meters: float
    privacy_aware_distance_meters: float


class WebPrivacyMetricsOut(Schema):
    privacy_perturbation: WebPrivacyPerturbationOut
    quality_of_service: WebQualityOfServiceOut


class WebPrivacyAwareOut(Schema):
    level: str
    default_level: str
    track: WebTrackOut
    diary: WebDiaryOut
    significant_places: list[WebSignificantPlaceOut]
    metrics: WebPrivacyMetricsOut


class WebTripDashboardOut(Schema):
    owner: WebUserSummaryOut
    trip: WebTripDetailOut
    track: WebTrackOut
    diary: WebDiaryOut
    privacy_aware: WebPrivacyAwareOut


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


def _privacy_track_out(trip: Trip, *, level: str) -> WebTrackOut:
    cloaked_line = cloak_linestring(trip.path, level=level)
    return WebTrackOut(
        trip_id=trip.id,
        point_count=cloaked_line.point_count if cloaked_line is not None else 0,
        distance_meters=cloaked_line.distance_meters if cloaked_line is not None else 0,
        geojson=line_geojson(cloaked_line),
    )


def _segment_path_geojson(segment: MobilitySegment, *, level: str | None) -> dict | None:
    """Move path as GeoJSON; raw when `level` is None, cloaked otherwise."""
    if segment.kind != MobilitySegment.Kind.MOVE or segment.path is None:
        return None
    if level is None:
        return json.loads(segment.path.geojson)
    return line_geojson(cloak_linestring(segment.path, level=level))


def _diary_out(trip: Trip, *, level: str | None = None) -> WebDiaryOut:
    persisted_segments = list(trip.segments.all())
    virtual_stop_intervals = list(trip.virtual_stop_intervals.all())
    projected = project_trip_diary_segments(trip)
    gps = list(trip.gps_points.order_by("timestamp"))
    confirmed = list(
        HabitualPlace.objects.filter(
            user_id=trip.user_id,
            state=HabitualPlace.State.CONFIRMED,
        )
    )
    source_intervals = stop_like_source_intervals(
        persisted_segments,
        virtual_stop_intervals,
    )
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
                path_geojson=_segment_path_geojson(segment, level=level),
                place=_segment_place_out_cached(
                    segment,
                    level=level,
                    gps=gps,
                    confirmed=confirmed,
                    source_intervals=source_intervals,
                ),
            )
            for segment in projected
        ],
    )


def _segment_place_out_cached(
    segment: MobilitySegment,
    *,
    level: str | None,
    gps,
    confirmed,
    source_intervals,
) -> WebDiaryPlaceOut | None:
    if segment.kind != MobilitySegment.Kind.STOP:
        return None
    summary = visible_stop_summary(segment, source_intervals, gps, confirmed)
    if summary is None:
        return None
    masked = level not in (None, UserPrivacySettings.Level.PRECISE)
    place = summary.matched_place
    center = Point(summary.lon, summary.lat, srid=4326)
    if masked:
        center = cloak_point(center, level=level)
    return WebDiaryPlaceOut(
        center_geojson=point_geojson(center),
        label=(
            PRIVACY_AWARE_STOP_LABEL
            if masked
            else place_label(place) if place is not None else "Sosta rilevata"
        ),
        radius_meters=0 if place is None else place.radius_meters,
    )


def _saved_privacy_level(trip: Trip) -> str:
    settings, _ = UserPrivacySettings.objects.get_or_create(user=trip.user)
    return settings.level


def _resolve_privacy_level(trip: Trip, requested: str | None) -> str:
    """Pick the level for a privacy-aware view without touching the saved one.

    No query param means "use the owner's saved Preferenza Privacy"; a preview
    query param is honoured only after validation, so an Operatore Web can
    compare levels without mutating the user's preference.
    """
    if requested is None:
        return _saved_privacy_level(trip)
    if requested not in UserPrivacySettings.Level.values:
        raise HttpError(400, "Livello privacy non valido")
    return requested


def _privacy_significant_places_out(
    trip: Trip,
    *,
    level: str,
) -> list[WebSignificantPlaceOut]:
    masked = level != UserPrivacySettings.Level.PRECISE
    projected_segments = project_trip_diary_segments(trip)
    gps = list(trip.gps_points.order_by("timestamp"))
    confirmed = list(
        HabitualPlace.objects.filter(
            user_id=trip.user_id,
            state=HabitualPlace.State.CONFIRMED,
        )
    )
    source_intervals = stop_like_source_intervals(
        list(trip.segments.all()),
        list(trip.virtual_stop_intervals.all()),
    )
    aggregated = {}
    for segment in projected_segments:
        if segment.kind != MobilitySegment.Kind.STOP:
            continue
        place = visible_stop_place(segment, source_intervals, gps, confirmed)
        if place is None:
            continue
        bucket = aggregated.setdefault(
            place.id,
            {
                "place": place,
                "dwell_seconds": 0,
            },
        )
        bucket["dwell_seconds"] += int(
            (segment.end_timestamp - segment.start_timestamp).total_seconds()
        )
    return [
        WebSignificantPlaceOut(
            center_geojson=point_geojson(cloak_point(item["place"].center, level=level)),
            label=PRIVACY_AWARE_STOP_LABEL if masked else place_label(item["place"]),
            radius_meters=item["place"].radius_meters,
            dwell_seconds=item["dwell_seconds"],
        )
        for item in aggregated.values()
    ]


def _privacy_metrics_out(trip: Trip, *, level: str) -> WebPrivacyMetricsOut:
    metrics = privacy_metrics(trip.path, level=level)
    return WebPrivacyMetricsOut(
        privacy_perturbation=WebPrivacyPerturbationOut(
            mean_meters=metrics.perturbation_mean_meters,
            max_meters=metrics.perturbation_max_meters,
            sample_count=metrics.perturbation_sample_count,
        ),
        quality_of_service=WebQualityOfServiceOut(
            relative_distance_error=metrics.relative_distance_error,
            private_distance_meters=metrics.private_distance_meters,
            privacy_aware_distance_meters=metrics.privacy_aware_distance_meters,
        ),
    )


def _privacy_aware_out(trip: Trip, *, requested_level: str | None) -> WebPrivacyAwareOut:
    default_level = _saved_privacy_level(trip)
    level = _resolve_privacy_level(trip, requested_level)
    precise = level == UserPrivacySettings.Level.PRECISE
    return WebPrivacyAwareOut(
        level=level,
        default_level=default_level,
        track=_track_out(trip) if precise else _privacy_track_out(trip, level=level),
        diary=_diary_out(trip, level=None if precise else level),
        significant_places=_privacy_significant_places_out(trip, level=level),
        metrics=_privacy_metrics_out(trip, level=level),
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
def get_web_trip_dashboard(
    request,
    user_id: int,
    trip_id: int,
    level: str | None = None,
):
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
        "privacy_aware": _privacy_aware_out(trip, requested_level=level),
    }
