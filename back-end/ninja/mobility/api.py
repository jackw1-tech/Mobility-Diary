import asyncio
import json

from django.contrib.gis.db.models.functions import AsGeoJSON, Length
from django.contrib.gis.geos import Point
from django.db.models import BooleanField, Case, Count, Value, When
from django.http import StreamingHttpResponse
from django.shortcuts import aget_object_or_404, get_object_or_404
from django.utils import timezone
from ninja import Router
from ninja.errors import HttpError

from accounts.auth import mobile_bearer_auth

from .diary_events import (
    DIARY_ENRICHMENT_FAILED_REASON,
    DIARY_STATUS_ENRICHED,
    DIARY_STATUS_EVENT,
    DIARY_STATUS_FAILED,
    create_async_redis_client,
    diary_status_channel,
    diary_status_payload,
)
from .models import GpsPoint, HarJob, SensorWindow, StateTransition, Trip, TripIngestion
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
    TripListItemOut,
    TripOut,
)
from .tasks import process_trip_har

router = Router(tags=["mobility"])

_TRIP_EVENT_MAX_SECONDS = 300


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
            path_geojson=json.loads(seg.path.geojson) if seg.path is not None else None,
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


def _sse_event(event: str, data: dict) -> str:
    payload = json.dumps(data, separators=(",", ":"))
    return f"event: {event}\ndata: {payload}\n\n"


def _sse_raw_event(event: str, data: str) -> str:
    return f"event: {event}\ndata: {data}\n\n"


async def _is_trip_diary_processed(trip_id: int, user_id: int) -> bool:
    return await Trip.objects.filter(
        id=trip_id,
        user_id=user_id,
        status=Trip.Status.PROCESSED,
    ).aexists()


async def _trip_diary_failure_reason(trip_id: int, user_id: int) -> str | None:
    failed = await TripIngestion.objects.filter(
        trip_id=trip_id,
        user_id=user_id,
        raw_status=TripIngestion.PhaseStatus.FAILED_FINAL,
    ).aexists()
    return DIARY_ENRICHMENT_FAILED_REASON if failed else None


async def _trip_diary_status_payload(trip_id: int, user_id: int) -> dict | None:
    if await _is_trip_diary_processed(trip_id, user_id):
        return diary_status_payload(trip_id, DIARY_STATUS_ENRICHED)

    failure_reason = await _trip_diary_failure_reason(trip_id, user_id)
    if failure_reason is not None:
        return diary_status_payload(
            trip_id,
            DIARY_STATUS_FAILED,
            reason=failure_reason,
        )
    return None


async def _next_diary_status_message(pubsub) -> str:
    async for message in pubsub.listen():
        if message.get("type") != "message":
            continue
        data = message.get("data")
        if isinstance(data, bytes):
            return data.decode("utf-8")
        return str(data)
    raise asyncio.CancelledError


async def _trip_diary_event_stream(
    trip_id: int,
    user_id: int,
    *,
    max_seconds: int = _TRIP_EVENT_MAX_SECONDS,
):
    channel = diary_status_channel(trip_id)
    redis_client = create_async_redis_client()
    pubsub = redis_client.pubsub()
    subscribed = False
    try:
        await pubsub.subscribe(channel)
        subscribed = True

        current_payload = await _trip_diary_status_payload(trip_id, user_id)
        if current_payload is not None:
            yield _sse_event(DIARY_STATUS_EVENT, current_payload)
            return

        try:
            message = await asyncio.wait_for(
                _next_diary_status_message(pubsub),
                timeout=max_seconds,
            )
        except TimeoutError:
            yield ": timeout\n\n"
            return

        yield _sse_raw_event(DIARY_STATUS_EVENT, message)
    finally:
        if subscribed:
            await pubsub.unsubscribe(channel)
        await pubsub.aclose()
        await redis_client.aclose()


@router.get("/trips/{trip_id}/events", auth=mobile_bearer_auth)
async def trip_events(request, trip_id: int):
    await aget_object_or_404(Trip, id=trip_id, user_id=request.auth.user_id)
    response = StreamingHttpResponse(
        _trip_diary_event_stream(trip_id, request.auth.user_id),
        content_type="text/event-stream",
    )
    response["Cache-Control"] = "no-cache"
    response["X-Accel-Buffering"] = "no"
    return response


@router.get("/trips", response=list[TripListItemOut], auth=mobile_bearer_auth)
def list_trips(request):
    """Elenco dei viaggi dell'utente, dal piu' recente.

    `has_track` e' calcolato a DB (path non null) senza caricare la geometria,
    cosi' la UI sa se il pulsante "Vedi su mappa" puo' mostrare qualcosa.
    """
    return list(
        Trip.objects.filter(user_id=request.auth.user_id)
        .annotate(
            has_track=Case(
                When(path__isnull=False, then=Value(True)),
                default=Value(False),
                output_field=BooleanField(),
            )
        )
        .order_by("-started_at")
        .values("id", "started_at", "ended_at", "status", "distance_meters", "has_track")
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
