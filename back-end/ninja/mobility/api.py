from django.shortcuts import get_object_or_404
from ninja import Router

from .models import GpsPoint, HarJob, SensorWindow, Trip
from .schemas import (
    GpsPointIn,
    HarJobOut,
    HealthOut,
    SensorWindowBatchIn,
    TripCreateIn,
    TripOut,
)
from .tasks import process_trip_har

router = Router(tags=["mobility"])


@router.get("/health", response=HealthOut)
def health(request):
    return {"status": "ok"}


@router.post("/trips", response=TripOut)
def create_trip(request, payload: TripCreateIn):
    trip = Trip.objects.create(device_id=payload.device_id)
    return trip


@router.post("/trips/{trip_id}/gps-points")
def add_gps_point(request, trip_id: int, payload: GpsPointIn):
    trip = get_object_or_404(Trip, id=trip_id)
    GpsPoint.objects.create(trip=trip, **payload.dict())
    return {"status": "stored"}


@router.post("/trips/{trip_id}/sensor-windows")
def add_sensor_windows(request, trip_id: int, payload: SensorWindowBatchIn):
    trip = get_object_or_404(Trip, id=trip_id)
    windows = [
        SensorWindow(
            trip=trip,
            start_timestamp=window.start_timestamp,
            end_timestamp=window.end_timestamp,
            sample_count=window.sample_count,
            frequency_hz=window.frequency_hz,
            matrix=window.matrix,
            object_key=window.object_key,
        )
        for window in payload.windows
    ]
    SensorWindow.objects.bulk_create(windows)
    return {"status": "stored", "count": len(windows)}


@router.post("/trips/{trip_id}/process-har", response=HarJobOut)
def enqueue_har_job(request, trip_id: int):
    trip = get_object_or_404(Trip, id=trip_id)
    job = HarJob.objects.create(trip=trip, kind=HarJob.Kind.FINAL_TRIP)
    process_trip_har.delay(job.id)
    return job

