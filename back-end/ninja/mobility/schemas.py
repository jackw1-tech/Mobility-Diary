from datetime import datetime
from decimal import Decimal
from typing import Any

from ninja import Schema


class HealthOut(Schema):
    status: str


class TripCreateIn(Schema):
    device_id: str


class TripOut(Schema):
    id: int
    device_id: str
    status: str
    started_at: datetime
    ended_at: datetime | None


class GpsPointIn(Schema):
    timestamp: datetime
    latitude: Decimal
    longitude: Decimal
    speed_mps: float = 0
    accuracy_meters: float | None = None


class SensorWindowIn(Schema):
    start_timestamp: datetime
    end_timestamp: datetime
    sample_count: int
    frequency_hz: int
    matrix: list[list[float]] | None = None
    object_key: str = ""


class SensorWindowBatchIn(Schema):
    windows: list[SensorWindowIn]


class HarJobOut(Schema):
    id: int
    trip_id: int
    kind: str
    status: str
    result: dict[str, Any] | None
    error: str

