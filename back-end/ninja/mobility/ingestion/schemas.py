from datetime import datetime

from ninja import Schema
from pydantic import Field


class IngestionCreateIn(Schema):
    client_session_id: str
    schema_version: int = 1
    started_at: datetime | None = None
    ended_at: datetime | None = None
    timezone: str = ""
    device_id: str = ""
    app_version: str = ""
    device_platform: str = ""
    # {"gps_points": 1, "state_transitions": 1}
    expected_core_parts: dict[str, int]
    # {"sensor_windows": 6}
    expected_raw_parts: dict[str, int] = Field(default_factory=dict)


class IngestionStartIn(Schema):
    client_session_id: str
    schema_version: int = 1
    started_at: datetime | None = None
    timezone: str = ""
    device_id: str = ""
    app_version: str = ""
    device_platform: str = ""


class IngestionStartOut(Schema):
    ingestion_id: int
    client_session_id: str
    device_id: str
    recording_started_at: datetime
    already_exists: bool


class ActiveIngestionOut(Schema):
    ingestion_id: int
    client_session_id: str
    device_id: str
    recording_started_at: datetime
    last_seen_at: datetime | None


class ActiveIngestionConflictOut(Schema):
    detail: str
    active_ingestion: ActiveIngestionOut


class IngestionAbandonIn(Schema):
    device_id: str


class IngestionAbandonOut(Schema):
    ingestion_id: int
    recording_abandoned_at: datetime


class IngestionHeartbeatIn(Schema):
    client_session_id: str
    device_id: str


class IngestionHeartbeatOut(Schema):
    ingestion_id: int
    last_seen_at: datetime


class IngestionCreateOut(Schema):
    ingestion_id: int
    core_status: str
    raw_status: str
    already_exists: bool


class InlineGpsPointIn(Schema):
    timestamp: datetime
    latitude: float
    longitude: float
    speed_mps: float = 0
    accuracy_meters: float | None = None


class InlineStateTransitionIn(Schema):
    timestamp: datetime
    from_state: str
    to_state: str
    reason: str = ""
    sigma: float | None = None
    speed_mps: float | None = None


class InlineCoreIn(Schema):
    ingestion_id: int | None = None
    client_session_id: str
    core_payload_sha256: str
    schema_version: int = 1
    started_at: datetime | None = None
    ended_at: datetime | None = None
    timezone: str = ""
    device_id: str = ""
    app_version: str = ""
    device_platform: str = ""
    gps_points: list[InlineGpsPointIn] = Field(default_factory=list)
    state_transitions: list[InlineStateTransitionIn] = Field(default_factory=list)
    expected_raw_parts: dict[str, int] = Field(default_factory=dict)


class InlineCoreOut(Schema):
    ingestion_id: int
    trip_id: int | None
    core_status: str
    raw_status: str
    gps_points: int
    state_transitions: int
    path_points: int
    distance_meters: float
    map_available: bool


class PartPresignIn(Schema):
    kind: str
    sequence: int = 1
    sha256: str
    size_bytes: int


class PartPresignOut(Schema):
    object_key: str
    upload_url: str
    upload_headers: dict[str, str]
    expires_in: int


class PartConfirmIn(Schema):
    kind: str
    sequence: int = 1
    sha256: str


class PartConfirmOut(Schema):
    ingestion_id: int
    kind: str
    sequence: int
    status: str


class CompleteIn(Schema):
    manifest_sha256: str = ""
    total_parts: int | None = None


class CompleteOut(Schema):
    ingestion_id: int
    core_status: str
    raw_status: str


class PartStateOut(Schema):
    kind: str
    sequence: int


class IngestionStatusOut(Schema):
    ingestion_id: int
    core_status: str
    raw_status: str
    core_ingestion_mode: str
    received_core_parts: list[PartStateOut]
    missing_core_parts: list[PartStateOut]
    received_raw_parts: list[PartStateOut]
    missing_raw_parts: list[PartStateOut]
    trip_id: int | None
    map_available: bool
    error: str | None
    core_progress: int
    raw_progress: int
