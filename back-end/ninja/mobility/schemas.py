from datetime import datetime
from typing import Any

from ninja import Schema


class HealthOut(Schema):
    status: str


class TripCreateIn(Schema):
    device_id: str
    # UUID della sessione FSM locale: chiave di idempotenza (un Trip per sessione).
    client_session_id: str | None = None


class TripOut(Schema):
    id: int
    device_id: str
    status: str
    client_session_id: str | None = None
    started_at: datetime
    ended_at: datetime | None


class GpsPointIn(Schema):
    timestamp: datetime
    lat: float
    lon: float
    speed_mps: float = 0
    accuracy_meters: float | None = None


class GpsPointBatchIn(Schema):
    points: list[GpsPointIn]


class SensorWindowIn(Schema):
    start_timestamp: datetime
    end_timestamp: datetime
    sample_count: int
    frequency_hz: int
    matrix: list[list[float]] | None = None
    object_key: str = ""


class SensorWindowBatchIn(Schema):
    windows: list[SensorWindowIn]


class StateTransitionIn(Schema):
    from_state: str
    to_state: str
    reason: str = ""
    timestamp: datetime
    sigma: float | None = None
    speed_mps: float | None = None


class StateTransitionBatchIn(Schema):
    transitions: list[StateTransitionIn]


class StoredOut(Schema):
    status: str
    count: int = 0


class HarJobOut(Schema):
    id: int
    trip_id: int
    kind: str
    status: str
    result: dict[str, Any] | None
    error: str


class PlaceOut(Schema):
    id: int
    lat: float
    lon: float
    # Etichetta visualizzabile: nome manuale, categoria, o "luogo abituale".
    label: str
    # Categoria chiusa (casa/universita/...) se etichettato, altrimenti vuota.
    category: str = ""


class PlaceVisitOut(Schema):
    lat: float
    lon: float
    started_at: datetime
    ended_at: datetime
    point_count: int


class PlaceLabelIn(Schema):
    # Categoria chiusa (casa/universita/lavoro/palestra/altro) o "" per azzerare.
    category: str = ""
    custom_name: str = ""


class PlaceMiningStatusOut(Schema):
    status: str
    requested_at: datetime | None = None
    started_at: datetime | None = None
    finished_at: datetime | None = None
    error_message: str = ""
    rerun_requested: bool = False


class PlaceMutationBlockedOut(Schema):
    detail: str
    code: str
    status: str


class PlaceReviewOut(Schema):
    id: int
    lat: float
    lon: float
    radius_meters: float
    # CANDIDATE / CONFIRMED / REJECTED
    state: str
    # Etichetta visualizzabile (nome manuale, categoria, o "luogo abituale").
    label: str
    category: str
    custom_name: str
    # Contesto: perche' il luogo e' stato proposto/confermato.
    visit_count: int
    distinct_days: int
    # Evidenza di mappa: le visite che compongono il luogo.
    visits: list[PlaceVisitOut]


class SegmentOut(Schema):
    kind: str
    start_timestamp: datetime
    end_timestamp: datetime
    activity_label: str
    distance_meters: float
    path_geojson: dict[str, Any] | None = None
    place: PlaceOut | None = None


class DiaryOut(Schema):
    trip_id: int
    status: str
    processed: bool
    segments: list[SegmentOut]
    places: list[PlaceOut]


class TrackOut(Schema):
    trip_id: int
    point_count: int
    distance_meters: float
    geojson: dict[str, Any] | None
    bbox: list[float] | None = None


class TripListItemOut(Schema):
    id: int
    started_at: datetime
    ended_at: datetime | None
    status: str
    distance_meters: float | None
    note: str
    # True se esiste una traiettoria disegnabile (path con >= 2 punti).
    has_track: bool
    is_reloadable: bool
    is_derived: bool
    can_delete: bool
    can_toggle_reloadable: bool
    can_edit_note: bool


class TripReloadableUpdateIn(Schema):
    is_reloadable: bool


class TripNoteUpdateIn(Schema):
    note: str = ""


class TripReloadIn(Schema):
    reload_request_id: str
    scheduled_start_at: datetime | None = None


class TripReloadSlotOut(Schema):
    started_at: datetime
    ended_at: datetime


class TripReloadSlotsOut(Schema):
    source_trip_id: int
    duration_seconds: int
    slots: list[TripReloadSlotOut]


class TripReloadOut(Schema):
    ingestion_id: int
    trip_id: int
    core_status: str
    raw_status: str
    gps_points: int
    state_transitions: int
    path_points: int
    distance_meters: float
    map_available: bool


class ReplayPointOut(Schema):
    timestamp: datetime
    latitude: float
    longitude: float
    speed_mps: float
    accuracy_meters: float | None


class ReplayTransitionOut(Schema):
    timestamp: datetime
    from_state: str
    to_state: str


class ReplayDataOut(Schema):
    source_trip_id: int
    gps_points: list[ReplayPointOut]
    state_transitions: list[ReplayTransitionOut]


class RouteAssistantClassifyIn(Schema):
    # Finestra grezza accelerometro+giroscopio: HAR_WINDOW_SAMPLE_COUNT righe x 6.
    samples: list[list[float]]


class RouteAssistantClassifyOut(Schema):
    label: str  # walking | cycling | driving | idle
    confidence: float


class RouteAssistantSensorWindowOut(Schema):
    # Finestra grezza (500x6) estratta dal viaggio sorgente per il replay live.
    samples: list[list[float]]


class PrivacyExportSegmentOut(Schema):
    kind: str
    start_label: str
    end_label: str
    activity_label: str
    # Titolo mostrabile: attivita' per i MOVE, etichetta reale solo se la vista
    # e' `precise`, altrimenti una dicitura generica per le soste.
    title: str
    point_count: int
    # Coordinate privacy-aware (cloaked) per i MOVE; vuota per le soste.
    coordinates: list[list[float]]


class PrivacyExportOut(Schema):
    trip_id: int
    level: str
    # False solo per `precise`: l'export non protegge la geometria.
    protected: bool
    # True quando le coordinate sono celle cloaked e non letture GPS reali.
    approximated_coordinates: bool
    cell_size_meters: int | None
    text: str
    segments: list[PrivacyExportSegmentOut]


class AnalyticsCategorySliceOut(Schema):
    # Categoria di Mobilita: fermo | a_piedi | corsa | in_bici | in_auto.
    category: str
    seconds: float
    distance_meters: float


class AnalyticsBucketOut(Schema):
    # Un intervallo della Finestra Analitica (un giorno o una settimana).
    label: str
    categories: list[AnalyticsCategorySliceOut]


class AnalyticsRouteOut(Schema):
    origin_label: str
    destination_label: str
    trip_count: int


class AnalyticsHeatPointOut(Schema):
    lat: float
    lon: float
    weight: float


class AnalyticsWeeklyHeatmapOut(Schema):
    label: str
    trip_ids: list[int]
    habitual_places: list[AnalyticsHeatPointOut]


class AnalyticsOut(Schema):
    """Analitiche Personali: bucket finestrati + aggregati cumulativi (ADR 0030)."""

    granularity: str
    # False quando l'utente non ha ancora Viaggi sincronizzati (empty state).
    has_data: bool
    buckets: list[AnalyticsBucketOut]
    prevalent_mode: str | None
    frequent_routes: list[AnalyticsRouteOut]
    heatmap: list[AnalyticsHeatPointOut]
    weekly_heatmaps: list[AnalyticsWeeklyHeatmapOut]
