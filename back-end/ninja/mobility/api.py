import asyncio
import json

from django.contrib.gis.geos import Point
from django.db import transaction
from django.http import StreamingHttpResponse
from django.shortcuts import aget_object_or_404, get_object_or_404
from django.utils import timezone
from ninja import Router
from ninja.errors import HttpError
from ninja.responses import Status

from accounts.schemas import MessageOut
from accounts.auth_mobile.auth import mobile_bearer_auth
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
from .diary_export import build_trip_privacy_export
from .replay_raw import source_sensor_window_at
from .selectors.places import (
    place_mining_status_row_for_user,
    place_review_queryset_for_user,
)
from .selectors.trips import (
    reloadable_trip_list_items_for_user,
    trip_list_items_for_user,
    trip_track_for_user,
)
from .selectors.analytics import personal_analytics_for_user
from .services.places import (
    PlaceMutationBlockedError,
    PlaceServiceError,
    confirm_place_for_user,
    label_place_for_user,
    reactivate_place_for_user,
    reject_place_for_user,
)
from .services.reload import (
    ReloadServiceError,
    reload_slots_for_trip as reload_slots_for_trip_service,
    reload_trip_from_source,
)
from .services.route_assistant import (
    RouteAssistantValidationError,
    classify_route_assistant_samples,
)
from .services.trips import (
    TripServiceError,
    delete_trip as delete_trip_service,
    update_trip_note as update_trip_note_service,
    update_trip_reloadable as update_trip_reloadable_service,
)
from .models import (
    GpsPoint,
    HabitualPlace,
    HarJob,
    MobilitySegment,
    SensorWindow,
    StateTransition,
    Trip,
    TripIngestion,
)
from .significant_places import (
    place_label,
    stop_like_source_intervals,
    visible_stop_summary,
)
from .schemas import (
    AnalyticsOut,
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
    ReplayDataOut,
    RouteAssistantClassifyIn,
    RouteAssistantClassifyOut,
    RouteAssistantSensorWindowOut,
    SegmentOut,
    SensorWindowBatchIn,
    StateTransitionBatchIn,
    StoredOut,
    TrackOut,
    TripNoteUpdateIn,
    TripReloadIn,
    TripReloadableUpdateIn,
    TripReloadOut,
    TripReloadSlotsOut,
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


@router.post(
    "/route-assistant/classify",
    response=RouteAssistantClassifyOut,
    auth=mobile_bearer_auth,
)
def classify_route_assistant_window(request, payload: RouteAssistantClassifyIn):
    try:
        result = classify_route_assistant_samples(payload.samples)
    except RouteAssistantValidationError as exc:
        raise HttpError(exc.status_code, exc.message) from exc
    return {"label": result.label, "confidence": result.confidence}


def _six_axis_matrix(matrix: list[list[float]] | None) -> list[list[float]] | None:
    if matrix is None:
        return None
    return [row[:6] for row in matrix]


@router.post("/trips", response=TripOut, auth=mobile_bearer_auth)
def create_trip(request, payload: TripCreateIn):
    user_id = request.auth.user_id
    now = timezone.now()
    if payload.client_session_id:
        # Idempotente: un Trip per sessione FSM locale. Un retry non duplica.
        trip, _ = Trip.objects.get_or_create(
            client_session_id=payload.client_session_id,
            defaults={
                "user_id": user_id,
                "device_id": payload.device_id,
                "started_at": now,
            },
        )
        return trip
    return Trip.objects.create(
        user_id=user_id, device_id=payload.device_id, started_at=now
    )


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
            matrix=_six_axis_matrix(w.matrix),
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
    return PlaceMiningStatusOut(**place_mining_status_row_for_user(user_id))


def _place_blocked_status(exc: PlaceMutationBlockedError):
    return Status(409, PlaceMutationBlockedOut(**exc.block.__dict__))


def _raise_place_service_error(exc: PlaceServiceError) -> None:
    raise HttpError(exc.status_code, exc.message) from exc


@router.get("/places", response=list[PlaceReviewOut], auth=mobile_bearer_auth)
def list_places(request):
    """Luoghi user-scoped per la review mobile, con evidenza di mappa.

    Restituisce tutti i luoghi dell'utente (il client raggruppa per stato); ogni
    luogo porta il contesto (visite, giorni distinti) e le visite di supporto.
    """
    places = place_review_queryset_for_user(request.auth.user_id)
    return [_place_review_out(place) for place in places]


@router.get("/places/status", response=PlaceMiningStatusOut, auth=mobile_bearer_auth)
def get_places_status(request):
    return _place_mining_status_out(request.auth.user_id)


@router.post(
    "/places/{place_id}/confirm",
    response=_PLACE_REVIEW_RESPONSES,
    auth=mobile_bearer_auth,
)
def confirm_place(request, place_id: int):
    try:
        place = confirm_place_for_user(request.auth.user_id, place_id)
    except PlaceMutationBlockedError as exc:
        return _place_blocked_status(exc)
    except PlaceServiceError as exc:
        _raise_place_service_error(exc)
    return _place_review_out(place)


@router.post(
    "/places/{place_id}/reject",
    response=_PLACE_REVIEW_RESPONSES,
    auth=mobile_bearer_auth,
)
def reject_place(request, place_id: int):
    try:
        place = reject_place_for_user(request.auth.user_id, place_id)
    except PlaceMutationBlockedError as exc:
        return _place_blocked_status(exc)
    except PlaceServiceError as exc:
        _raise_place_service_error(exc)
    return _place_review_out(place)


@router.post(
    "/places/{place_id}/reactivate",
    response=_PLACE_REVIEW_RESPONSES,
    auth=mobile_bearer_auth,
)
def reactivate_place(request, place_id: int):
    """Riattiva un luogo rifiutato: torna candidato e rientra nel flusso automatico."""
    try:
        place = reactivate_place_for_user(request.auth.user_id, place_id)
    except PlaceMutationBlockedError as exc:
        return _place_blocked_status(exc)
    except PlaceServiceError as exc:
        _raise_place_service_error(exc)
    return _place_review_out(place)


@router.post(
    "/places/{place_id}/label",
    response={**_PLACE_REVIEW_RESPONSES, 422: MessageOut},
    auth=mobile_bearer_auth,
)
def label_place(request, place_id: int, payload: PlaceLabelIn):
    try:
        place = label_place_for_user(
            request.auth.user_id,
            place_id,
            category=payload.category,
            custom_name=payload.custom_name,
        )
    except PlaceMutationBlockedError as exc:
        return _place_blocked_status(exc)
    except PlaceServiceError as exc:
        _raise_place_service_error(exc)
    return _place_review_out(place)


def _saved_privacy_level(user_id: int) -> str:
    settings, _ = UserPrivacySettings.objects.get_or_create(user_id=user_id)
    return settings.level


def _privacy_export_segment_out(segment) -> PrivacyExportSegmentOut:
    return PrivacyExportSegmentOut(
        kind=segment.kind,
        start_label=segment.start_label,
        end_label=segment.end_label,
        activity_label=segment.activity_label,
        title=segment.title,
        point_count=segment.point_count,
        coordinates=segment.coordinates,
    )


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
    export = build_trip_privacy_export(trip, level=level)
    return PrivacyExportOut(
        trip_id=export.trip_id,
        level=export.level,
        protected=export.protected,
        approximated_coordinates=export.approximated_coordinates,
        cell_size_meters=export.cell_size_meters,
        text=export.text,
        segments=[
            _privacy_export_segment_out(segment) for segment in export.segments
        ],
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


def _raise_trip_service_error(exc: TripServiceError) -> None:
    raise HttpError(exc.status_code, exc.message) from exc


@router.get("/trips", response=list[TripListItemOut], auth=mobile_bearer_auth)
def list_trips(request):
    """Elenco dei viaggi dell'utente, dal piu' recente.

    `has_track` e' calcolato a DB (path non null) senza caricare la geometria,
    cosi' la UI sa se il pulsante "Vedi su mappa" puo' mostrare qualcosa.
    """
    return trip_list_items_for_user(request.auth.user_id)


@router.get(
    "/trips/reloadable",
    response=list[TripListItemOut],
    auth=mobile_bearer_auth,
)
def list_reloadable_trips(request):
    return reloadable_trip_list_items_for_user(request.auth.user_id)


@router.patch(
    "/trips/{trip_id}/reloadable",
    response=TripListItemOut,
    auth=mobile_bearer_auth,
)
def update_trip_reloadable(request, trip_id: int, payload: TripReloadableUpdateIn):
    try:
        return update_trip_reloadable_service(
            user_id=request.auth.user_id,
            trip_id=trip_id,
            is_reloadable=payload.is_reloadable,
        )
    except TripServiceError as exc:
        _raise_trip_service_error(exc)


@router.patch(
    "/trips/{trip_id}/note",
    response=TripListItemOut,
    auth=mobile_bearer_auth,
)
def update_trip_note(request, trip_id: int, payload: TripNoteUpdateIn):
    try:
        return update_trip_note_service(
            user_id=request.auth.user_id,
            trip_id=trip_id,
            note=payload.note,
        )
    except TripServiceError as exc:
        _raise_trip_service_error(exc)


@router.delete(
    "/trips/{trip_id}",
    response={204: None},
    auth=mobile_bearer_auth,
)
def delete_trip(request, trip_id: int):
    try:
        delete_trip_service(user_id=request.auth.user_id, trip_id=trip_id)
    except TripServiceError as exc:
        _raise_trip_service_error(exc)
    return Status(204, None)


@router.get(
    "/trips/reloadable/{trip_id}/replay-data",
    response=ReplayDataOut,
    auth=mobile_bearer_auth,
)
def get_replay_data(request, trip_id: int):
    source = get_object_or_404(
        Trip,
        id=trip_id,
        user_id=request.auth.user_id,
        is_reloadable=True,
        status__in=[Trip.Status.CLOSED, Trip.Status.PROCESSED],
    )
    return {
        "source_trip_id": source.id,
        "gps_points": source.gps_points.order_by("timestamp"),
        "state_transitions": source.state_transitions.order_by("timestamp"),
    }


@router.get(
    "/trips/reloadable/{trip_id}/sensor-window",
    response=RouteAssistantSensorWindowOut,
    auth=mobile_bearer_auth,
)
def get_reloadable_sensor_window(request, trip_id: int, offset_seconds: int):
    source = get_object_or_404(
        Trip,
        id=trip_id,
        user_id=request.auth.user_id,
        is_reloadable=True,
        status__in=[Trip.Status.CLOSED, Trip.Status.PROCESSED],
    )
    samples = source_sensor_window_at(source, offset_seconds)
    if samples is None:
        raise HttpError(404, "finestra sensori non disponibile per l'offset")
    return {"samples": samples}


def _raise_reload_service_error(exc: ReloadServiceError) -> None:
    raise HttpError(exc.status_code, exc.message) from exc


@router.get(
    "/trips/reloadable/{trip_id}/slots",
    response=TripReloadSlotsOut,
    auth=mobile_bearer_auth,
)
def list_reload_slots(
    request,
    trip_id: int,
    days: int = 14,
    step_minutes: int = 15,
    limit: int = 100,
):
    try:
        return reload_slots_for_trip_service(
            user_id=request.auth.user_id,
            trip_id=trip_id,
            days=days,
            step_minutes=step_minutes,
            limit=limit,
        )
    except ReloadServiceError as exc:
        _raise_reload_service_error(exc)


@router.post(
    "/trips/reloadable/{trip_id}/reload",
    response=TripReloadOut,
    auth=mobile_bearer_auth,
)
def reload_trip(request, trip_id: int, payload: TripReloadIn):
    try:
        return reload_trip_from_source(
            user_id=request.auth.user_id,
            trip_id=trip_id,
            reload_request_id=payload.reload_request_id,
            scheduled_start_at=payload.scheduled_start_at,
        )
    except ReloadServiceError as exc:
        _raise_reload_service_error(exc)


@router.get("/trips/{trip_id}/track", response=TrackOut, auth=mobile_bearer_auth)
def get_trip_track(request, trip_id: int):
    track = trip_track_for_user(trip_id, request.auth.user_id)
    if track is None:
        raise HttpError(404, "Trip non trovato")
    return TrackOut(**track)


@router.get("/analytics", response=AnalyticsOut, auth=mobile_bearer_auth)
def get_personal_analytics(request, granularity: str = "day", tz: str = "UTC"):
    """Analitiche Personali aggregate cross-Viaggio dell'utente (ADR 0030).

    `granularity` (Finestra Analitica): day = un bucket per ogni giorno, week =
    un bucket per ogni settimana, dal Viaggio meno recente dell'utente al piu'
    recente (bucket vuoti inclusi). `tz` e' il fuso locale del dispositivo per
    il bucketing. Modalita' prevalente, Percorsi Frequenti e heatmap sono
    cumulativi su tutta la storia.
    """
    return personal_analytics_for_user(
        user_id=request.auth.user_id,
        granularity=granularity,
        tz=tz,
    )
