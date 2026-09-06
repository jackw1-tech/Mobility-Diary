import json

from django.shortcuts import get_object_or_404
from ninja import Router
from ninja.errors import HttpError
from ninja.responses import Status

import accounts.repositories as accounts_repositories
from accounts.schemas import MessageOut
from accounts.auth_mobile.auth import mobile_bearer_auth

from .diary_export import build_trip_privacy_export
from .private_diary_cache import (
    cache_diary,
    get_cached_diary,
    get_places_version,
)
from .replay_raw import source_sensor_window_at
from .selectors.places import (
    place_mining_status_row_for_user,
    place_review_queryset_for_user,
)
from .selectors.trips import (
    reloadable_trip_list_items_for_user,
    trip_diary_enrichment_failed,
    trip_list_items_for_user,
    trip_track_for_user,
)
from .services.analytics import personal_analytics_for_user
from .services.diary_view import build_private_diary
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
from .models import Trip
from .significant_places import place_label
from .schemas import (
    AnalyticsOut,
    DiaryOut,
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
    TrackOut,
    TripNoteUpdateIn,
    TripReloadIn,
    TripReloadableUpdateIn,
    TripReloadOut,
    TripReloadSlotsOut,
    TripListItemOut,
)

router = Router(tags=["mobility"])

DIARY_ENRICHMENT_FAILED_REASON = "diary_enrichment_failed"
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
    match univoco, anche l'etichetta del Luogo Confermato piu' vicino. La
    proiezione vera e propria vive in `services.diary_view.build_private_diary`
    ed e' condivisa con la dashboard web (stessa regola, stesso posto).
    """
    trip = get_object_or_404(Trip, id=trip_id, user_id=request.user.user_id)
    failure_reason = (
        DIARY_ENRICHMENT_FAILED_REASON
        if trip_diary_enrichment_failed(trip_id, request.user.user_id)
        else None
    )

    places_version = get_places_version(request.user.user_id)
    if trip.status == Trip.Status.PROCESSED:
        diary_segments = get_cached_diary(trip_id, places_version)
        # Una lista vuota puo' essere stata scritta da una versione precedente
        # mentre HAR era ancora in corso. Ricostruirla impedisce di restituire
        # processed=true con segmenti obsoleti e costa solo per il raro diario
        # realmente vuoto.
        if not diary_segments:
            diary_segments = build_private_diary(trip)
            cache_diary(trip_id, places_version, diary_segments)
    else:
        # I risultati intermedi non sono cacheabili: stato e segmenti vengono
        # aggiornati asincronicamente dalla pipeline HAR.
        diary_segments = build_private_diary(trip)

    segments: list[SegmentOut] = []
    overlaid: dict[int, PlaceOut] = {}
    for seg in diary_segments:
        place_out = None
        if seg.place is not None:
            place_out = _visible_stop_place_out(seg.place)
            if seg.place.matched_place is not None:
                overlaid[seg.place.matched_place.id] = _place_out(seg.place.matched_place)
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
        enrichment_failed=failure_reason is not None,
        enrichment_failure_reason=failure_reason,
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


def _place_blocked_status(exc: PlaceMutationBlockedError):
    return Status(409, PlaceMutationBlockedOut(**exc.block.__dict__))


@router.get("/places", response=list[PlaceReviewOut], auth=mobile_bearer_auth)
def list_places(request):
    """Luoghi user-scoped per la review mobile, con evidenza di mappa.

    Restituisce tutti i luoghi dell'utente (il client raggruppa per stato); ogni
    luogo porta il contesto (visite, giorni distinti) e le visite di supporto.
    """
    places = place_review_queryset_for_user(request.user.user_id)
    return [_place_review_out(place) for place in places]


@router.get("/places/status", response=PlaceMiningStatusOut, auth=mobile_bearer_auth)
def get_places_status(request):
    return PlaceMiningStatusOut(
        **place_mining_status_row_for_user(request.user.user_id)
    )


@router.post(
    "/places/{place_id}/confirm",
    response=_PLACE_REVIEW_RESPONSES,
    auth=mobile_bearer_auth,
)
def confirm_place(request, place_id: int):
    try:
        place = confirm_place_for_user(request.user.user_id, place_id)
    except PlaceMutationBlockedError as exc:
        return _place_blocked_status(exc)
    except PlaceServiceError as exc:
        raise HttpError(exc.status_code, exc.message) from exc
    return _place_review_out(place)


@router.post(
    "/places/{place_id}/reject",
    response=_PLACE_REVIEW_RESPONSES,
    auth=mobile_bearer_auth,
)
def reject_place(request, place_id: int):
    try:
        place = reject_place_for_user(request.user.user_id, place_id)
    except PlaceMutationBlockedError as exc:
        return _place_blocked_status(exc)
    except PlaceServiceError as exc:
        raise HttpError(exc.status_code, exc.message) from exc
    return _place_review_out(place)


@router.post(
    "/places/{place_id}/reactivate",
    response=_PLACE_REVIEW_RESPONSES,
    auth=mobile_bearer_auth,
)
def reactivate_place(request, place_id: int):
    """Riattiva un luogo rifiutato: torna candidato e rientra nel flusso automatico."""
    try:
        place = reactivate_place_for_user(request.user.user_id, place_id)
    except PlaceMutationBlockedError as exc:
        return _place_blocked_status(exc)
    except PlaceServiceError as exc:
        raise HttpError(exc.status_code, exc.message) from exc
    return _place_review_out(place)


@router.post(
    "/places/{place_id}/label",
    response={**_PLACE_REVIEW_RESPONSES, 422: MessageOut},
    auth=mobile_bearer_auth,
)
def label_place(request, place_id: int, payload: PlaceLabelIn):
    try:
        place = label_place_for_user(
            request.user.user_id,
            place_id,
            category=payload.category,
            custom_name=payload.custom_name,
        )
    except PlaceMutationBlockedError as exc:
        return _place_blocked_status(exc)
    except PlaceServiceError as exc:
        raise HttpError(exc.status_code, exc.message) from exc
    return _place_review_out(place)


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
    trip = get_object_or_404(Trip, id=trip_id, user_id=request.user.user_id)
    settings = accounts_repositories.get_or_create_privacy_settings(request.user.user_id)
    level = settings.level
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


@router.get("/trips", response=list[TripListItemOut], auth=mobile_bearer_auth)
def list_trips(request):
    return trip_list_items_for_user(request.user.user_id)


@router.get(
    "/trips/reloadable",
    response=list[TripListItemOut],
    auth=mobile_bearer_auth,
)
def list_reloadable_trips(request):
    return reloadable_trip_list_items_for_user(request.user.user_id)


@router.patch(
    "/trips/{trip_id}/reloadable",
    response=TripListItemOut,
    auth=mobile_bearer_auth,
)
def update_trip_reloadable(request, trip_id: int, payload: TripReloadableUpdateIn):
    try:
        return update_trip_reloadable_service(
            user_id=request.user.user_id,
            trip_id=trip_id,
            is_reloadable=payload.is_reloadable,
        )
    except TripServiceError as exc:
        raise HttpError(exc.status_code, exc.message) from exc


@router.patch(
    "/trips/{trip_id}/note",
    response=TripListItemOut,
    auth=mobile_bearer_auth,
)
def update_trip_note(request, trip_id: int, payload: TripNoteUpdateIn):
    try:
        return update_trip_note_service(
            user_id=request.user.user_id,
            trip_id=trip_id,
            note=payload.note,
        )
    except TripServiceError as exc:
        raise HttpError(exc.status_code, exc.message) from exc


@router.delete(
    "/trips/{trip_id}",
    response={204: None},
    auth=mobile_bearer_auth,
)
def delete_trip(request, trip_id: int):
    try:
        delete_trip_service(user_id=request.user.user_id, trip_id=trip_id)
    except TripServiceError as exc:
        raise HttpError(exc.status_code, exc.message) from exc
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
        user_id=request.user.user_id,
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
        user_id=request.user.user_id,
        is_reloadable=True,
        status__in=[Trip.Status.CLOSED, Trip.Status.PROCESSED],
    )
    samples = source_sensor_window_at(source, offset_seconds)
    if samples is None:
        raise HttpError(404, "finestra sensori non disponibile per l'offset")
    return {"samples": samples}


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
            user_id=request.user.user_id,
            trip_id=trip_id,
            days=days,
            step_minutes=step_minutes,
            limit=limit,
        )
    except ReloadServiceError as exc:
        raise HttpError(exc.status_code, exc.message) from exc


@router.post(
    "/trips/reloadable/{trip_id}/reload",
    response=TripReloadOut,
    auth=mobile_bearer_auth,
)
def reload_trip(request, trip_id: int, payload: TripReloadIn):
    try:
        return reload_trip_from_source(
            user_id=request.user.user_id,
            trip_id=trip_id,
            reload_request_id=payload.reload_request_id,
            scheduled_start_at=payload.scheduled_start_at,
        )
    except ReloadServiceError as exc:
        raise HttpError(exc.status_code, exc.message) from exc


@router.get("/trips/{trip_id}/track", response=TrackOut, auth=mobile_bearer_auth)
def get_trip_track(request, trip_id: int):
    track = trip_track_for_user(trip_id, request.user.user_id)
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
        user_id=request.user.user_id,
        granularity=granularity,
        tz=tz,
    )
