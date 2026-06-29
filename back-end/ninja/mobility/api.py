import asyncio
import json
import math
from collections import Counter, defaultdict
from datetime import datetime, time, timedelta
from datetime import timezone as dt_timezone
from zoneinfo import ZoneInfo

from django.contrib.gis.db.models.functions import AsGeoJSON, Length
from django.contrib.gis.geos import Point
from django.db.models import BooleanField, Case, Count, Value, When
from django.http import StreamingHttpResponse
from django.shortcuts import aget_object_or_404, get_object_or_404
from django.utils import timezone
from ninja import Router
from ninja.errors import HttpError
from ninja.responses import Status

from accounts.schemas import MessageOut
from accounts.auth import mobile_bearer_auth
from accounts.models import UserPrivacySettings

from .diary_events import (
    DIARY_ENRICHMENT_FAILED_REASON,
    DIARY_STATUS_ENRICHED,
    DIARY_STATUS_EVENT,
    DIARY_STATUS_FAILED,
    create_async_redis_client,
    diary_status_channel,
    diary_status_payload,
)
from .diary_projection import project_diary_segments
from .models import (
    GpsPoint,
    HabitualPlace,
    HarJob,
    MobilitySegment,
    PlaceMiningStatus,
    SensorWindow,
    StateTransition,
    Trip,
    TripIngestion,
)
from .significant_places import (
    place_label,
    stop_like_source_intervals,
    visible_stop_place,
    visible_stop_summary,
)
from .privacy import (
    PRIVACY_AWARE_STOP_LABEL,
    cloak_linestring,
    line_geojson,
    privacy_cell_size_meters,
)
from .schemas import (
    AnalyticsBucketOut,
    AnalyticsCategorySliceOut,
    AnalyticsHeatPointOut,
    AnalyticsOut,
    AnalyticsRouteOut,
    DiaryOut,
    GpsPointBatchIn,
    HarJobOut,
    HealthOut,
    PlaceLabelIn,
    PlaceMiningStatusOut,
    PlaceMutationBlockedOut,
    PlaceOut,
    PlaceReviewOut,
    PlaceVisitOut,
    PrivacyExportOut,
    PrivacyExportSegmentOut,
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
NEUTRAL_VISIBLE_STOP_TITLE = "Sosta rilevata"
_PLACE_REVIEW_RESPONSES = {200: PlaceReviewOut, 409: PlaceMutationBlockedOut}


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
        label=place_label(place),
        category=place.category,
    )


def _visible_stop_place_out(summary) -> PlaceOut:
    place = summary.matched_place
    return PlaceOut(
        id=0 if place is None else place.id,
        lat=summary.lat,
        lon=summary.lon,
        label=NEUTRAL_VISIBLE_STOP_TITLE if place is None else place_label(place),
        category="" if place is None else place.category,
    )


@router.get("/trips/{trip_id}/diary", response=DiaryOut, auth=mobile_bearer_auth)
def get_trip_diary(request, trip_id: int):
    """Diario read-time delle soste visibili, con overlay dei Luoghi Confermati.

    I MobilitySegment persistiti non vengono riscritti: la sosta prende a tempo
    di lettura la propria posizione dai GpsPoint dell'intervallo e, se c'e' un
    match univoco, anche l'etichetta del Luogo Confermato piu' vicino.
    """
    trip = get_object_or_404(Trip, id=trip_id, user_id=request.auth.user_id)
    gps = list(trip.gps_points.order_by("timestamp"))
    confirmed = list(
        HabitualPlace.objects.filter(
            user_id=request.auth.user_id,
            state=HabitualPlace.State.CONFIRMED,
        )
    )
    persisted_segments = list(trip.segments.all())
    virtual_stop_intervals = list(trip.virtual_stop_intervals.all())
    source_intervals = stop_like_source_intervals(
        persisted_segments,
        virtual_stop_intervals,
    )
    segments: list[SegmentOut] = []
    overlaid: dict[int, PlaceOut] = {}
    for seg in project_diary_segments(persisted_segments, virtual_stop_intervals):
        place_out = None
        if seg.kind == MobilitySegment.Kind.STOP:
            summary = visible_stop_summary(seg, source_intervals, gps, confirmed)
            if summary is not None:
                place_out = _visible_stop_place_out(summary)
                if summary.matched_place is not None:
                    overlaid[summary.matched_place.id] = _place_out(summary.matched_place)
        segments.append(
            SegmentOut(
                kind=seg.kind,
                start_timestamp=seg.start_timestamp,
                end_timestamp=seg.end_timestamp,
                activity_label=seg.activity_label,
                distance_meters=seg.distance_meters,
                path_geojson=json.loads(seg.path.geojson) if seg.path is not None else None,
                place=place_out,
            )
        )
    return DiaryOut(
        trip_id=trip.id,
        status=trip.status,
        processed=trip.status == Trip.Status.PROCESSED,
        segments=segments,
        places=list(overlaid.values()),
    )


def _place_review_out(place) -> PlaceReviewOut:
    return PlaceReviewOut(
        id=place.id,
        lat=place.center.y,
        lon=place.center.x,
        radius_meters=place.radius_meters,
        state=place.state,
        label=place_label(place),
        category=place.category,
        custom_name=place.custom_name,
        visit_count=place.visit_count,
        distinct_days=place.distinct_days,
        visits=[
            PlaceVisitOut(
                lat=visit.center.y,
                lon=visit.center.x,
                started_at=visit.started_at,
                ended_at=visit.ended_at,
                point_count=visit.point_count,
            )
            for visit in place.visits.all()
        ],
    )


def _place_mining_status_out(user_id: int) -> PlaceMiningStatusOut:
    row = (
        PlaceMiningStatus.objects.filter(user_id=user_id)
        .values(
            "status",
            "requested_at",
            "started_at",
            "finished_at",
            "error_message",
            "rerun_requested",
        )
        .first()
    )
    return PlaceMiningStatusOut(
        **(
            row
            or {
                "status": PlaceMiningStatus.Status.IDLE,
                "error_message": "",
                "rerun_requested": False,
            }
        )
    )


def _place_mutation_block(user_id: int) -> PlaceMutationBlockedOut | None:
    status = (
        PlaceMiningStatus.objects.filter(user_id=user_id)
        .values_list("status", flat=True)
        .first()
        or PlaceMiningStatus.Status.IDLE
    )
    if status == PlaceMiningStatus.Status.SUCCEEDED:
        return None
    return PlaceMutationBlockedOut(
        detail="analisi dei luoghi abituali non completata",
        code="place_mining_not_ready",
        status=status,
    )


@router.get("/places", response=list[PlaceReviewOut], auth=mobile_bearer_auth)
def list_places(request):
    """Luoghi user-scoped per la review mobile, con evidenza di mappa.

    Restituisce tutti i luoghi dell'utente (il client raggruppa per stato); ogni
    luogo porta il contesto (visite, giorni distinti) e le visite di supporto.
    """
    places = (
        HabitualPlace.objects.filter(user_id=request.auth.user_id)
        .prefetch_related("visits")
        .order_by("state", "-visit_count")
    )
    return [_place_review_out(place) for place in places]


@router.get("/places/status", response=PlaceMiningStatusOut, auth=mobile_bearer_auth)
def get_places_status(request):
    return _place_mining_status_out(request.auth.user_id)


_VALID_PLACE_CATEGORIES = {choice.value for choice in HabitualPlace.Category}


def _owned_place(request, place_id: int) -> HabitualPlace:
    return get_object_or_404(
        HabitualPlace, id=place_id, user_id=request.auth.user_id
    )


def _save_review(place: HabitualPlace, fields: list[str]) -> PlaceReviewOut:
    place.save(update_fields=[*fields, "updated_at"])
    return _place_review_out(place)


@router.post(
    "/places/{place_id}/confirm",
    response=_PLACE_REVIEW_RESPONSES,
    auth=mobile_bearer_auth,
)
def confirm_place(request, place_id: int):
    place = _owned_place(request, place_id)
    if blocked := _place_mutation_block(request.auth.user_id):
        return Status(409, blocked)
    place.state = HabitualPlace.State.CONFIRMED
    place.manually_reviewed = True
    return _save_review(place, ["state", "manually_reviewed"])


@router.post(
    "/places/{place_id}/reject",
    response=_PLACE_REVIEW_RESPONSES,
    auth=mobile_bearer_auth,
)
def reject_place(request, place_id: int):
    place = _owned_place(request, place_id)
    if blocked := _place_mutation_block(request.auth.user_id):
        return Status(409, blocked)
    place.state = HabitualPlace.State.REJECTED
    place.manually_reviewed = True
    return _save_review(place, ["state", "manually_reviewed"])


@router.post(
    "/places/{place_id}/reactivate",
    response=_PLACE_REVIEW_RESPONSES,
    auth=mobile_bearer_auth,
)
def reactivate_place(request, place_id: int):
    """Riattiva un luogo rifiutato: torna candidato e rientra nel flusso automatico."""
    place = _owned_place(request, place_id)
    if blocked := _place_mutation_block(request.auth.user_id):
        return Status(409, blocked)
    place.state = HabitualPlace.State.CANDIDATE
    place.manually_reviewed = False
    return _save_review(place, ["state", "manually_reviewed"])


@router.post(
    "/places/{place_id}/label",
    response={**_PLACE_REVIEW_RESPONSES, 422: MessageOut},
    auth=mobile_bearer_auth,
)
def label_place(request, place_id: int, payload: PlaceLabelIn):
    if payload.category and payload.category not in _VALID_PLACE_CATEGORIES:
        raise HttpError(422, "categoria non valida")
    place = _owned_place(request, place_id)
    if blocked := _place_mutation_block(request.auth.user_id):
        return Status(409, blocked)
    place.category = payload.category
    place.custom_name = payload.custom_name
    place.manually_reviewed = True
    return _save_review(place, ["category", "custom_name", "manually_reviewed"])


def _saved_privacy_level(user_id: int) -> str:
    settings, _ = UserPrivacySettings.objects.get_or_create(user_id=user_id)
    return settings.level


def _export_segment_coordinates(segment, *, level: str) -> list[list[float]]:
    """Privacy-aware coordinates for a MOVE; cloaked unless the level is precise.

    A non-precise export never returns the original GPS readings, so the mobile
    text can label them as approximated without leaking the private geometry.
    """
    if segment.path is None:
        return []
    if privacy_cell_size_meters(level) is None:
        return [
            [round(float(lon), 7), round(float(lat), 7)]
            for lon, lat, *_ in segment.path.coords
        ]
    cloaked = line_geojson(cloak_linestring(segment.path, level=level))
    return cloaked["coordinates"] if cloaked is not None else []


def _export_segment(segment, *, level: str, stop_title: str) -> PrivacyExportSegmentOut:
    masked = privacy_cell_size_meters(level) is not None
    if segment.kind == MobilitySegment.Kind.MOVE:
        title = segment.activity_label.lower()
    elif masked:
        title = PRIVACY_AWARE_STOP_LABEL
    else:
        title = stop_title or NEUTRAL_VISIBLE_STOP_TITLE

    coordinates = (
        _export_segment_coordinates(segment, level=level)
        if segment.kind == MobilitySegment.Kind.MOVE
        else []
    )
    return PrivacyExportSegmentOut(
        kind=segment.kind,
        start_label=segment.start_timestamp.strftime("%H:%M"),
        end_label=segment.end_timestamp.strftime("%H:%M"),
        activity_label=segment.activity_label,
        title=title,
        point_count=len(coordinates),
        coordinates=coordinates,
    )


_ACTIVITY_LABELS_IT = {
    "WALKING": "a piedi",
    "RUNNING": "di corsa",
    "BIKING": "in bici",
    "MOVING_VEHICLE": "in veicolo",
    "IDLE": "fermo",
}


def _activity_label_it(activity_label: str) -> str:
    return _ACTIVITY_LABELS_IT.get(activity_label, activity_label.lower())


def _adjacent_stop_title(
    segments: list[PrivacyExportSegmentOut], index: int, *, step: int
) -> str | None:
    neighbour_index = index + step
    if not 0 <= neighbour_index < len(segments):
        return None
    neighbour = segments[neighbour_index]
    return neighbour.title if neighbour.kind == MobilitySegment.Kind.STOP else None


def _export_text(segments: list[PrivacyExportSegmentOut]) -> str:
    # Le etichette privacy-aware delle soste arrivano gia' filtrate da _export_segment.
    lines = []
    for index, segment in enumerate(segments):
        time_range = f"{segment.start_label}–{segment.end_label}"
        if segment.kind == MobilitySegment.Kind.MOVE:
            from_title = _adjacent_stop_title(segments, index, step=-1)
            to_title = _adjacent_stop_title(segments, index, step=1)
            activity = _activity_label_it(segment.activity_label)
            if from_title and to_title:
                description = f"spostamento da {from_title} a {to_title}, modalita' prevalente: {activity}"
            else:
                description = f"spostamento {activity}"
        else:
            description = f"permanenza in {segment.title}"
        lines.append(f"{time_range}, {description}")
    return "\n".join(lines)


@router.get(
    "/trips/{trip_id}/privacy-export",
    response=PrivacyExportOut,
    auth=mobile_bearer_auth,
)
def get_trip_privacy_export(request, trip_id: int):
    """Vista Privacy-Aware testuale per l'export mobile.

    Usa la Preferenza Privacy salvata dall'utente; il diario mobile normale
    resta privato e preciso. Per i livelli non-precise la geometria e' cloaked
    e le soste usano una dicitura generica.
    """
    trip = get_object_or_404(Trip, id=trip_id, user_id=request.auth.user_id)
    level = _saved_privacy_level(request.auth.user_id)
    persisted_segments = list(trip.segments.all())
    virtual_stop_intervals = list(trip.virtual_stop_intervals.all())
    gps = list(trip.gps_points.order_by("timestamp"))
    confirmed = list(
        HabitualPlace.objects.filter(
            user_id=request.auth.user_id,
            state=HabitualPlace.State.CONFIRMED,
        )
    )
    source_intervals = stop_like_source_intervals(
        persisted_segments,
        virtual_stop_intervals,
    )
    projected_segments = project_diary_segments(
        persisted_segments,
        virtual_stop_intervals,
    )
    segments = [
        _export_segment(
            segment,
            level=level,
            stop_title=(
                place_label(place)
                if segment.kind == MobilitySegment.Kind.STOP
                and (place := visible_stop_place(segment, source_intervals, gps, confirmed))
                is not None
                else ""
            ),
        )
        for segment in projected_segments
    ]
    return PrivacyExportOut(
        trip_id=trip.id,
        level=level,
        protected=level != UserPrivacySettings.Level.PRECISE,
        approximated_coordinates=privacy_cell_size_meters(level) is not None,
        cell_size_meters=privacy_cell_size_meters(level),
        text=_export_text(segments),
        segments=segments,
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


# Categoria di Mobilita: mappatura 1-a-1 dalla Etichetta di Attivita.
_CATEGORY_BY_ACTIVITY = {
    "IDLE": "fermo",
    "WALKING": "a_piedi",
    "RUNNING": "corsa",
    "BIKING": "in_bici",
    "MOVING_VEHICLE": "in_auto",
}
_MOBILITY_CATEGORIES = ["fermo", "a_piedi", "corsa", "in_bici", "in_auto"]
_ITALIAN_WEEKDAYS = ["Lun", "Mar", "Mer", "Gio", "Ven", "Sab", "Dom"]


def _analytics_zone(tz: str):
    """Fuso per il bucketing: offset firmato in minuti (dal mobile), nome IANA, o UTC."""
    try:
        return dt_timezone(timedelta(minutes=int(tz)))
    except ValueError:
        pass
    try:
        return ZoneInfo(tz)
    except Exception:  # noqa: BLE001 — tz arbitraria dal client, fallback sicuro
        return ZoneInfo("UTC")


def _bucket_start_of(local_date, granularity: str):
    """Inizio del bucket (lunedi' per la settimana, il giorno stesso altrimenti)."""
    if granularity == "week":
        return local_date - timedelta(days=local_date.weekday())
    return local_date


def _analytics_buckets(user_id: int, granularity: str, zone: ZoneInfo):
    is_week = granularity == "week"
    today = timezone.now().astimezone(zone).date()
    step = timedelta(weeks=1) if is_week else timedelta(days=1)
    count = 8 if is_week else 7
    anchor = _bucket_start_of(today, granularity)
    starts = [anchor - step * i for i in range(count - 1, -1, -1)]
    index_by_start = {start: i for i, start in enumerate(starts)}
    totals = [{c: [0.0, 0.0] for c in _MOBILITY_CATEGORIES} for _ in starts]

    window_start = datetime.combine(starts[0], time.min, tzinfo=zone)
    rows = MobilitySegment.objects.filter(
        trip__user_id=user_id, start_timestamp__gte=window_start
    ).values("start_timestamp", "end_timestamp", "activity_label", "distance_meters")

    for row in rows:
        local_date = row["start_timestamp"].astimezone(zone).date()
        index = index_by_start.get(_bucket_start_of(local_date, granularity))
        if index is None:
            continue
        category = _CATEGORY_BY_ACTIVITY.get(row["activity_label"], "fermo")
        seconds = (row["end_timestamp"] - row["start_timestamp"]).total_seconds()
        cell = totals[index][category]
        cell[0] += max(0.0, seconds)
        cell[1] += float(row["distance_meters"] or 0)

    return [
        AnalyticsBucketOut(
            label=start.strftime("%d/%m")
            if granularity == "week"
            else _ITALIAN_WEEKDAYS[start.weekday()],
            categories=[
                AnalyticsCategorySliceOut(
                    category=c, seconds=cell[c][0], distance_meters=cell[c][1]
                )
                for c in _MOBILITY_CATEGORIES
            ],
        )
        for start, cell in zip(starts, totals)
    ]


def _analytics_heatmap(user_id: int) -> list[AnalyticsHeatPointOut]:
    """Mappa di Frequentazione: Luoghi Significativi confermati pesati per visite."""
    places = HabitualPlace.objects.filter(
        user_id=user_id, state=HabitualPlace.State.CONFIRMED
    ).only("center", "visit_count")
    return [
        AnalyticsHeatPointOut(
            lat=place.center.y, lon=place.center.x, weight=float(place.visit_count)
        )
        for place in places
    ]


def _prevalent_mode(user_id: int) -> str | None:
    """Categoria di Mobilita con piu' tempo totale su tutta la storia, Fermo escluso."""
    rows = MobilitySegment.objects.filter(trip__user_id=user_id).values(
        "activity_label", "start_timestamp", "end_timestamp"
    )
    totals: dict[str, float] = defaultdict(float)
    for row in rows:
        category = _CATEGORY_BY_ACTIVITY.get(row["activity_label"], "fermo")
        if category == "fermo":
            continue
        totals[category] += (
            row["end_timestamp"] - row["start_timestamp"]
        ).total_seconds()
    return max(totals, key=totals.get) if totals else None


def _haversine_meters(lat1, lon1, lat2, lon2) -> float:
    radius = 6371000.0
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(
        dlambda / 2
    ) ** 2
    return 2 * radius * math.asin(math.sqrt(a))


def _nearest_place(coord, places):
    """Luogo Significativo piu' vicino a (lon, lat) entro il suo raggio (min 150 m)."""
    lon, lat = coord[0], coord[1]
    best, best_distance = None, None
    for place in places:
        distance = _haversine_meters(lat, lon, place.center.y, place.center.x)
        if distance <= max(place.radius_meters or 0, 150.0) and (
            best_distance is None or distance < best_distance
        ):
            best, best_distance = place, distance
    return best


def _frequent_routes(user_id: int, limit: int = 5) -> list[AnalyticsRouteOut]:
    """Percorsi Frequenti: coppie Origine->Destinazione tra Luoghi Significativi."""
    places = list(
        HabitualPlace.objects.filter(
            user_id=user_id, state=HabitualPlace.State.CONFIRMED
        ).only("center", "radius_meters", "custom_name", "category")
    )
    if not places:
        return []

    pairs: Counter = Counter()
    trips = Trip.objects.filter(user_id=user_id, path__isnull=False).only("path")
    for trip in trips:
        coords = trip.path.coords
        if len(coords) < 2:
            continue
        origin = _nearest_place(coords[0], places)
        destination = _nearest_place(coords[-1], places)
        if origin is None or destination is None or origin.id == destination.id:
            continue
        pairs[(origin.id, destination.id)] += 1

    by_id = {place.id: place for place in places}
    return [
        AnalyticsRouteOut(
            origin_label=place_label(by_id[origin_id]),
            destination_label=place_label(by_id[destination_id]),
            trip_count=count,
        )
        for (origin_id, destination_id), count in pairs.most_common(limit)
    ]


@router.get("/analytics", response=AnalyticsOut, auth=mobile_bearer_auth)
def get_personal_analytics(request, granularity: str = "day", tz: str = "UTC"):
    """Analitiche Personali aggregate cross-Viaggio dell'utente (ADR 0030).

    `granularity` (Finestra Analitica): day = ultimi 7 giorni, week = ultime 8
    settimane. `tz` e' il fuso locale del dispositivo per il bucketing. Modalita'
    prevalente, Percorsi Frequenti e heatmap sono cumulativi su tutta la storia.
    """
    user_id = request.auth.user_id
    granularity = granularity if granularity in {"day", "week"} else "day"
    return AnalyticsOut(
        granularity=granularity,
        has_data=Trip.objects.filter(user_id=user_id).exists(),
        buckets=_analytics_buckets(user_id, granularity, _analytics_zone(tz)),
        prevalent_mode=_prevalent_mode(user_id),
        frequent_routes=_frequent_routes(user_id),
        heatmap=_analytics_heatmap(user_id),
    )
