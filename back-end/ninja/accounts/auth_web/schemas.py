from datetime import datetime
from typing import Any

from ninja import Schema

from ..schemas import UserOut


class WebLoginIn(Schema):
    email: str
    password: str


class WebRefreshTokenIn(Schema):
    refresh_token: str


class WebAuthOut(Schema):
    user: UserOut
    access_token: str
    refresh_token: str
    token_type: str
    access_expires_at: datetime
    refresh_expires_at: datetime


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
