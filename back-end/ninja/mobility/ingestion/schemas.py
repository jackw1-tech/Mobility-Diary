from datetime import datetime

from ninja import Schema
from pydantic import Field


class IngestionStartIn(Schema):
    client_session_id: str = Field(min_length=1, max_length=64)
    started_at: datetime | None = None
    device_id: str = ""
    source_trip_id: int | None = None


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


class InlineGpsPointIn(Schema):
    timestamp: datetime
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
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
    cutoff_source_timestamp: datetime | None = None
    client_session_id: str
    started_at: datetime | None = None
    ended_at: datetime | None = None
    device_id: str = ""
    gps_points: list[InlineGpsPointIn] = Field(default_factory=list)
    state_transitions: list[InlineStateTransitionIn] = Field(default_factory=list)
    expected_raw_parts: int = 0


class InlineCoreOut(Schema):
    ingestion_id: int
    trip_id: int | None
    core_status: str
    raw_status: str
    map_available: bool


class PartPresignIn(Schema):
    sequence: int = 1
    sha256: str


class PartPresignOut(Schema):
    object_key: str
    upload_url: str
    upload_headers: dict[str, str]
    expires_in: int


class PartConfirmIn(Schema):
    sequence: int = 1
    sha256: str


class PartConfirmOut(Schema):
    ingestion_id: int
    sequence: int
    status: str


class CompleteIn(Schema):
    total_parts: int | None = None


class CompleteOut(Schema):
    ingestion_id: int
    core_status: str
    raw_status: str


class PartStateOut(Schema):
    sequence: int


class IngestionStatusOut(Schema):
    ingestion_id: int
    core_status: str
    raw_status: str
    missing_raw_parts: list[PartStateOut]
    trip_id: int | None
    map_available: bool
