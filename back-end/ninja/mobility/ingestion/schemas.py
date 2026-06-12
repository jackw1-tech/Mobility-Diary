from datetime import datetime

from ninja import Schema


class IngestionCreateIn(Schema):
    client_session_id: str
    schema_version: int = 1
    started_at: datetime | None = None
    ended_at: datetime | None = None
    timezone: str = ""
    device_id: str = ""
    app_version: str = ""
    device_platform: str = ""
    # {"gps_points": 1, "state_transitions": 1, "sensor_windows": 6}
    expected_parts: dict[str, int]


class IngestionCreateOut(Schema):
    ingestion_id: int
    status: str
    already_exists: bool


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
    status: str


class PartStateOut(Schema):
    kind: str
    sequence: int


class IngestionStatusOut(Schema):
    ingestion_id: int
    status: str
    received_parts: list[PartStateOut]
    missing_parts: list[PartStateOut]
    trip_id: int | None
    error: str | None
    progress: int
