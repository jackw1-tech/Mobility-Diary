"""Punto con tutte tutte le rotte lato admin
"""

from __future__ import annotations

from ninja import Router
from ninja.errors import HttpError

from .. import repositories as accounts_repositories
from mobility.models import Trip
from mobility.selectors import trips as trips_repository
from mobility.services import dashboard as dashboard_service
from mobility.services.diary_view import build_private_diary
from mobility.services.trips import RawTripFilterParams, TripValidationError, parse_trip_filters

from .auth import web_dashboard_auth
from .schemas import (
    WebAxisStatsOut,
    WebDiaryOut,
    WebDiaryPlaceOut,
    WebDiarySegmentOut,
    WebMotionStatsOut,
    WebPrivacyAwareOut,
    WebPrivacyMetricsOut,
    WebPrivacyPerturbationOut,
    WebQualityOfServiceOut,
    WebSensorGapOut,
    WebSignificantPlaceOut,
    WebTrackOut,
    WebTripDashboardOut,
    WebTripDetailOut,
    WebUserOverviewOut,
    WebUserTripsOut,
)

router = Router(tags=["web-users"])


def _diary_segment_out(segment: dashboard_service.DiarySegmentRowView) -> WebDiarySegmentOut:
    return WebDiarySegmentOut(
        kind=segment.kind,
        start_timestamp=segment.start_timestamp,
        end_timestamp=segment.end_timestamp,
        activity_label=segment.activity_label,
        distance_meters=segment.distance_meters,
        path_geojson=segment.path_geojson,
        place=_diary_place_out(segment.place),
    )


def _diary_place_out(
    place: dashboard_service.DiarySegmentPlaceView | None,
) -> WebDiaryPlaceOut | None:
    if place is None:
        return None
    return WebDiaryPlaceOut(
        center_geojson=place.center_geojson,
        label=place.label,
        radius_meters=place.radius_meters,
    )


def _diary_out(diary: dashboard_service.DiaryView) -> WebDiaryOut:
    return WebDiaryOut(
        trip_id=diary.trip_id,
        status=diary.status,
        processed=diary.processed,
        segments=[_diary_segment_out(segment) for segment in diary.segments],
    )


def _track_out(track: dashboard_service.TrackView) -> WebTrackOut:
    return WebTrackOut(
        trip_id=track.trip_id,
        point_count=track.point_count,
        distance_meters=track.distance_meters,
        geojson=track.geojson,
    )


def _significant_place_out(
    place: dashboard_service.SignificantPlaceView,
) -> WebSignificantPlaceOut:
    return WebSignificantPlaceOut(
        center_geojson=place.center_geojson,
        label=place.label,
        radius_meters=place.radius_meters,
        dwell_seconds=place.dwell_seconds,
    )


def _privacy_metrics_out(metrics) -> WebPrivacyMetricsOut:
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


def _sensor_gap_out(gap: dashboard_service.SensorGapView) -> WebSensorGapOut:
    return WebSensorGapOut(
        start_timestamp=gap.start_timestamp,
        end_timestamp=gap.end_timestamp,
        gap_seconds=gap.gap_seconds,
    )


def _motion_stats_out(stats: dashboard_service.MotionStatsView) -> WebMotionStatsOut:
    return WebMotionStatsOut(
        activity_label=stats.activity_label,
        sample_count=stats.sample_count,
        **{
            axis: WebAxisStatsOut(mean=axis_stats.mean, std=axis_stats.std)
            for axis, axis_stats in stats.axes.items()
        },
    )


def _privacy_aware_out(
    view: dashboard_service.PrivacyAwareView,
) -> WebPrivacyAwareOut:
    return WebPrivacyAwareOut(
        level=view.level,
        default_level=view.default_level,
        track=_track_out(view.track),
        diary=_diary_out(view.diary),
        significant_places=[
            _significant_place_out(place) for place in view.significant_places
        ],
        metrics=_privacy_metrics_out(view.metrics),
    )


def _owner_overview_or_404(user_id: int) -> dict:
    owner = accounts_repositories.web_user_overview_values(
        accounts_repositories.web_user_overviews_queryset().filter(id=user_id)
    ).first()
    if owner is None:
        raise HttpError(404, "Proprietario del Viaggio non trovato")
    return owner


@router.get("/users", response=list[WebUserOverviewOut], auth=web_dashboard_auth)
def list_web_users(request):
    return list(
        accounts_repositories.web_user_overview_values(
            accounts_repositories.web_user_overviews_queryset().order_by("email")
        )
    )


@router.get("/users/{user_id}/trips", response=WebUserTripsOut, auth=web_dashboard_auth)
def list_web_user_trips(request, user_id: int):
    owner = _owner_overview_or_404(user_id)
    try:
        filters = parse_trip_filters(
            RawTripFilterParams(
                started_from=request.GET.get("from"),
                started_to=request.GET.get("to"),
                status=request.GET.get("status"),
                processed=request.GET.get("processed"),
                has_track=request.GET.get("has_track"),
            )
        )
    except TripValidationError as exc:
        raise HttpError(exc.status_code, exc.message) from exc

    trips = trips_repository.apply_trip_filters(
        trips_repository.trips_queryset_for_user(user_id), filters
    )

    return {
        "owner": owner,
        "trips": trips_repository.web_trip_list_projection(trips),
    }


@router.get(
    "/users/{user_id}/motion-stats",
    response=list[WebMotionStatsOut],
    auth=web_dashboard_auth,
)
def get_web_user_motion_stats(request, user_id: int):
    _owner_overview_or_404(user_id)
    return [
        _motion_stats_out(stats)
        for stats in dashboard_service.motion_stats_by_activity(user_id)
    ]


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
    owner = _owner_overview_or_404(user_id)
    trip = trips_repository.trip_by_id_for_user(trip_id, user_id)
    if trip is None:
        raise HttpError(404, "Viaggio non trovato")

 
    precise_segments = build_private_diary(trip)

    try:
        privacy_aware = dashboard_service.privacy_aware_view(
            trip, requested_level=level, precise_segments=precise_segments
        )
    except dashboard_service.DashboardServiceError as exc:
        raise HttpError(exc.status_code, exc.message) from exc

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
        "track": _track_out(dashboard_service.track_view(trip)),
        "diary": _diary_out(
            dashboard_service.diary_view(trip, precise_segments=precise_segments)
        ),
        "privacy_aware": _privacy_aware_out(privacy_aware),
        "sensor_gaps": [
            _sensor_gap_out(gap) for gap in dashboard_service.sensor_gaps_view(trip)
        ],
    }
