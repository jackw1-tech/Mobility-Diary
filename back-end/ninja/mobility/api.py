import json

from django.contrib.gis.db.models.functions import AsGeoJSON, Length
from django.contrib.gis.geos import Point
from django.db.models import Count
from django.shortcuts import get_object_or_404
from django.utils import timezone
from ninja import Router
from ninja.errors import HttpError

from accounts.auth import mobile_bearer_auth

from .models import GpsPoint, HarJob, SensorWindow, StateTransition, Trip
from .schemas import (
    DiaryOut,
    GpsPointBatchIn,
    HarJobOut,
    HealthOut,
    PlaceOut,
    SegmentOut,
    SensorWindowBatchIn,
    StateTransitionBatchIn,
    StoredOut,
    TrackOut,
    TripCreateIn,
    TripOut,
)
from .tasks import process_trip_har

router = Router(tags=["mobility"])


@router.get("/health", response=HealthOut)
def health(request):
    return {"status": "ok"}


@router.post("/trips", response=TripOut, auth=mobile_bearer_auth)
def create_trip(request, payload: TripCreateIn):
    user_id = request.auth.user_id
    if payload.client_session_id:
        # Idempotente: un Trip per sessione FSM locale. Un retry non duplica.
        trip, _ = Trip.objects.get_or_create(
            client_session_id=payload.client_session_id,
            defaults={"user_id": user_id, "device_id": payload.device_id},
        )
        return trip
    return Trip.objects.create(user_id=user_id, device_id=payload.device_id)


@router.post("/trips/{trip_id}/gps-points", response=StoredOut, auth=mobile_bearer_auth)
def add_gps_points(request, trip_id: int, payload: GpsPointBatchIn):
    trip = get_object_or_404(Trip, id=trip_id, user_id=request.auth.user_id)
    rows = [
        GpsPoint(
            trip=trip,
            timestamp=p.timestamp,
            point=Point(p.lon, p.lat, srid=4326),
            speed_mps=p.speed_mps,
            accuracy_meters=p.accuracy_meters,
        )
        for p in payload.points
    ]
    GpsPoint.objects.bulk_create(rows, ignore_conflicts=True)
    return {"status": "stored", "count": len(rows)}


@router.post("/trips/{trip_id}/sensor-windows", response=StoredOut, auth=mobile_bearer_auth)
def add_sensor_windows(request, trip_id: int, payload: SensorWindowBatchIn):
    trip = get_object_or_404(Trip, id=trip_id, user_id=request.auth.user_id)
    rows = [
        SensorWindow(
            trip=trip,
            start_timestamp=w.start_timestamp,
            end_timestamp=w.end_timestamp,
            sample_count=w.sample_count,
            frequency_hz=w.frequency_hz,
            matrix=w.matrix,
            object_key=w.object_key,
        )
        for w in payload.windows
    ]
    SensorWindow.objects.bulk_create(rows, ignore_conflicts=True)
    return {"status": "stored", "count": len(rows)}


@router.post("/trips/{trip_id}/state-transitions", response=StoredOut, auth=mobile_bearer_auth)
def add_state_transitions(request, trip_id: int, payload: StateTransitionBatchIn):
    trip = get_object_or_404(Trip, id=trip_id, user_id=request.auth.user_id)
    rows = [
        StateTransition(
            trip=trip,
            from_state=t.from_state,
            to_state=t.to_state,
            reason=t.reason,
            timestamp=t.timestamp,
            sigma=t.sigma,
            speed_mps=t.speed_mps,
        )
        for t in payload.transitions
    ]
    StateTransition.objects.bulk_create(rows, ignore_conflicts=True)
    return {"status": "stored", "count": len(rows)}


@router.post("/trips/{trip_id}/close", response=TripOut, auth=mobile_bearer_auth)
def close_trip(request, trip_id: int):
    trip = get_object_or_404(Trip, id=trip_id, user_id=request.auth.user_id)
    if trip.status == Trip.Status.OPEN:
        trip.status = Trip.Status.CLOSED
    if trip.ended_at is None:
        trip.ended_at = timezone.now()
    trip.save(update_fields=["status", "ended_at", "updated_at"])
    return trip


@router.post("/trips/{trip_id}/process-har", response=HarJobOut, auth=mobile_bearer_auth)
def enqueue_har_job(request, trip_id: int):
    trip = get_object_or_404(Trip, id=trip_id, user_id=request.auth.user_id)
    job = HarJob.objects.create(trip=trip, kind=HarJob.Kind.FINAL_TRIP)
    process_trip_har.delay(job.id)
    return job


def _place_out(place) -> PlaceOut:
    return PlaceOut(
        id=place.id,
        lat=place.center.y,
        lon=place.center.x,
        radius_meters=place.radius_meters,
        dwell_seconds=place.dwell_seconds,
        label=place.label,
    )


@router.get("/trips/{trip_id}/diary", response=DiaryOut, auth=mobile_bearer_auth)
def get_trip_diary(request, trip_id: int):
    trip = get_object_or_404(Trip, id=trip_id, user_id=request.auth.user_id)
    places = list(trip.significant_places.all())
    place_by_id = {pl.id: _place_out(pl) for pl in places}
    segments = [
        SegmentOut(
            kind=seg.kind,
            start_timestamp=seg.start_timestamp,
            end_timestamp=seg.end_timestamp,
            activity_label=seg.activity_label,
            distance_meters=seg.distance_meters,
            place=place_by_id.get(seg.place_id),
        )
        for seg in trip.segments.all()
    ]
    return DiaryOut(
        trip_id=trip.id,
        status=trip.status,
        processed=trip.status == Trip.Status.PROCESSED,
        segments=segments,
        places=list(place_by_id.values()),
    )


@router.get("/trips/{trip_id}/track", response=TrackOut, auth=mobile_bearer_auth)
def get_trip_track(request, trip_id: int):
    row = (
        Trip.objects.filter(pk=trip_id, user_id=request.auth.user_id)
        .annotate(
            track_geojson=AsGeoJSON("path"),
            track_distance=Length("path"),
            point_count=Count("gps_points"),
        )
        .values("id", "track_geojson", "track_distance", "point_count")
        .first()
    )
    if row is None:
        raise HttpError(404, "Trip non trovato")

    distance = row["track_distance"]
    return TrackOut(
        trip_id=row["id"],
        point_count=row["point_count"],
        distance_meters=float(
            distance.m if hasattr(distance, "m") else distance or 0
        ),
        geojson=json.loads(row["track_geojson"])
        if row["track_geojson"] is not None
        else None,
    )
