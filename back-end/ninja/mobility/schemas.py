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
    # True se esiste una traiettoria disegnabile (path con >= 2 punti).
    has_track: bool


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
