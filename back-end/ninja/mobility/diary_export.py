from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta

from accounts.models import UserPrivacySettings

from .diary_projection import ProjectedDiarySegment
from .models import HabitualPlace, MobilitySegment, Trip
from .privacy import (
    PRIVACY_AWARE_STOP_LABEL,
    approximate_linestring,
    line_geojson,
    privacy_cell_size_meters,
)
from .selectors.places import confirmed_places_for_user
from .significant_places import VisibleStopDetails, place_label, project_diary_with_places

NEUTRAL_VISIBLE_STOP_TITLE = "Sosta rilevata"
APPROXIMATE_TIME_GRANULARITY = timedelta(minutes=5)

_ACTIVITY_LABELS_IT = {
    "WALKING": "a piedi",
    "RUNNING": "di corsa",
    "BIKING": "in bici",
    "MOVING_VEHICLE": "in veicolo",
    "IDLE": "fermo",
}

_APPROXIMATE_PLACE_LABELS = {
    HabitualPlace.Category.CASA: "area residenziale",
    HabitualPlace.Category.UNIVERSITA: "zona universitaria",
    HabitualPlace.Category.LAVORO: "area lavorativa",
    HabitualPlace.Category.PALESTRA: "area sportiva",
    HabitualPlace.Category.ALTRO: "area visitata",
}

_DAY_PERIODS = [
    ("notte", 0, 6),
    ("mattina", 6, 12),
    ("pomeriggio", 12, 18),
    ("sera", 18, 24),
]


@dataclass(frozen=True)
class DiaryExportSegment:
    kind: str
    start_timestamp: datetime
    end_timestamp: datetime
    start_label: str
    end_label: str
    activity_label: str
    title: str
    point_count: int
    coordinates: list[list[float]]
    duration: timedelta
    distance_meters: float


@dataclass(frozen=True)
class DiaryPrivacyExport:
    trip_id: int
    level: str
    protected: bool
    approximated_coordinates: bool
    cell_size_meters: int | None
    text: str
    segments: list[DiaryExportSegment]

# costruzione diario con livello di privacy impostato
def build_trip_privacy_export(trip: Trip, *, level: str) -> DiaryPrivacyExport:
    cell_size_meters = privacy_cell_size_meters(level)
    protected = level != UserPrivacySettings.Level.PRECISE
    persisted_segments = list(trip.segments.all())
    virtual_stop_intervals = list(trip.virtual_stop_intervals.all())
    gps = list(trip.gps_points.order_by("timestamp"))
    confirmed = confirmed_places_for_user(trip.user_id)
    segments = [
        _export_segment(segment, stop_details, level=level, protected=protected)
        for segment, stop_details in project_diary_with_places(
            persisted_segments, virtual_stop_intervals, gps, confirmed
        )
    ]
    if level == UserPrivacySettings.Level.AGGREGATED:
        return _aggregated_export(
            trip=trip,
            level=level,
            cell_size_meters=cell_size_meters,
            segments=segments,
        )
    return DiaryPrivacyExport(
        trip_id=trip.id,
        level=level,
        protected=protected,
        approximated_coordinates=cell_size_meters is not None,
        cell_size_meters=cell_size_meters,
        text=_export_text(
            trip_id=trip.id,
            level=level,
            protected=protected,
            cell_size_meters=cell_size_meters,
            segments=segments,
        ),
        segments=segments,
    )

# Funzione che costruisce il diario aggregato
def _aggregated_export(
    *,
    trip: Trip,
    level: str,
    cell_size_meters: int | None,
    segments: list[DiaryExportSegment],
) -> DiaryPrivacyExport:
    aggregated_segments = _aggregate_segments_by_period(segments)
    return DiaryPrivacyExport(
        trip_id=trip.id,
        level=level,
        protected=True,
        approximated_coordinates=True,
        cell_size_meters=cell_size_meters,
        text=_aggregated_text(
            trip_id=trip.id,
            cell_size_meters=cell_size_meters,
            segments=segments,
            aggregated_segments=aggregated_segments,
        ),
        segments=aggregated_segments,
    )

#Prende il singolo segmento e lo trasforma approssimandolo
   # Due possibili elmenti
    # Segmento Movimento , none
    # Segmento Fermo, nome | abitual pplace
def _export_segment(
    segment: ProjectedDiarySegment,
    stop_details: VisibleStopDetails | None,
    *,
    level: str,
    protected: bool,
) -> DiaryExportSegment:
    coordinates, distance_meters = _move_coordinates_and_distance(
        segment,
        level=level,
    )
    published_start = _published_start(segment.start_timestamp, protected=protected)
    published_end = _published_end(segment.end_timestamp, protected=protected)
    return DiaryExportSegment(
        kind=segment.kind,
        start_timestamp=published_start,
        end_timestamp=published_end,
        start_label=published_start.strftime("%H:%M"),
        end_label=published_end.strftime("%H:%M"),
        activity_label=segment.activity_label,
        title=_segment_title(segment, stop_details, protected=protected),
        point_count=len(coordinates),
        coordinates=coordinates,
        duration=published_end - published_start,
        distance_meters=distance_meters,
    )

#Per ogni segmento, ricalcola la nuova line string approssimata e quindi la nuova lunghezza del segmento
def _move_coordinates_and_distance(
    segment: ProjectedDiarySegment,
    *,
    level: str,
) -> tuple[list[list[float]], float]:
    #Le soste non hanno linee da mostrare
    if segment.kind != MobilitySegment.Kind.MOVE or segment.path is None:
        return [], 0.0

    #Livello precise -> restituisco le origniali
    if privacy_cell_size_meters(level) is None:
        return (
            [
                [round(float(lon), 7), round(float(lat), 7)]
                for lon, lat, *_ in segment.path.coords
            ],
            segment.distance_meters,
        )

    approximated = approximate_linestring(segment.path, level=level)
    geojson = line_geojson(approximated)
    return (
        [] if geojson is None else geojson["coordinates"],
        0.0 if approximated is None else approximated.distance_meters,
    )

#Raggruppa i singoli segmenti in fascia oraria
def _aggregate_segments_by_period(
    segments: list[DiaryExportSegment],
) -> list[DiaryExportSegment]:
    period_rows: list[DiaryExportSegment] = []
    if not segments:
        return period_rows
    base_day = segments[0].start_timestamp
    for period_name, start_hour, end_hour in _DAY_PERIODS:
        period_segments = [
            segment
            for segment in segments
            if _period_for_start_label(segment.start_label) == period_name
        ]
        if not period_segments:
            continue
        move_segments = [
            segment
            for segment in period_segments
            if segment.kind == MobilitySegment.Kind.MOVE
        ]
        stop_segments = [
            segment
            for segment in period_segments
            if segment.kind == MobilitySegment.Kind.STOP
        ]
        move_duration = sum(
            (segment.duration for segment in move_segments),
            timedelta(),
        )
        stop_duration = sum(
            (segment.duration for segment in stop_segments),
            timedelta(),
        )
        distance = sum(segment.distance_meters for segment in move_segments)
        activity = _prevalent_activity(move_segments)
        period_start = _period_timestamp(base_day, start_hour)
        period_end = _period_timestamp(base_day, end_hour)
        if move_segments:
            move_end = min(period_start + move_duration, period_end)
            period_rows.append(
                DiaryExportSegment(
                    kind=MobilitySegment.Kind.MOVE,
                    start_timestamp=period_start,
                    end_timestamp=move_end,
                    start_label=f"{start_hour:02d}:00",
                    end_label=move_end.strftime("%H:%M"),
                    activity_label=activity,
                    title=f"{period_name}: movimento aggregato",
                    point_count=0,
                    coordinates=[],
                    duration=move_duration,
                    distance_meters=distance,
                )
            )
        if stop_segments:
            stop_end = min(period_start + stop_duration, period_end)
            period_rows.append(
                DiaryExportSegment(
                    kind=MobilitySegment.Kind.STOP,
                    start_timestamp=period_start,
                    end_timestamp=stop_end,
                    start_label=f"{start_hour:02d}:00",
                    end_label=stop_end.strftime("%H:%M"),
                    activity_label="IDLE",
                    title=f"{period_name}: permanenza aggregata",
                    point_count=0,
                    coordinates=[],
                    duration=stop_duration,
                    distance_meters=0.0,
                )
            )
    return period_rows


def _segment_title(
    segment: ProjectedDiarySegment,
    stop_details: VisibleStopDetails | None,
    *,
    protected: bool,
) -> str:
    if segment.kind == MobilitySegment.Kind.MOVE:
        return _activity_label_it(segment.activity_label)

    place = None if stop_details is None else stop_details.matched_place
    if not protected:
        return NEUTRAL_VISIBLE_STOP_TITLE if place is None else place_label(place)
    if place is None:
        return PRIVACY_AWARE_STOP_LABEL
    return _APPROXIMATE_PLACE_LABELS.get(
        place.category,
        PRIVACY_AWARE_STOP_LABEL,
    )


def _export_text(
    *,
    trip_id: int,
    level: str,
    protected: bool,
    cell_size_meters: int | None,
    segments: list[DiaryExportSegment],
) -> str:
    lines = [
        f"Diario viaggio #{trip_id}",
        "Vista: condivisibile approssimata" if protected else "Vista: dettagliata",
        f"Privacy level: {level}",
    ]
    if cell_size_meters is not None:
        lines.append(f"Approssimazione spaziale: celle da {cell_size_meters} m")
        lines.append("Coordinate approssimate: non sono letture GPS originali.")
    else:
        lines.append("Coordinate precise: export non protetto.")
    lines.append("")
    for index, segment in enumerate(segments):
        lines.append(_segment_sentence(segments, index))
    return "\n".join(lines)

#Costruisce il testo del diario aggregato
def _aggregated_text(
    *,
    trip_id: int,
    cell_size_meters: int | None,
    segments: list[DiaryExportSegment],
    aggregated_segments: list[DiaryExportSegment],
) -> str:
    lines = [
        "DIARIO AGGREGATO",
        f"Viaggio #{trip_id}",
        "",
        "PRIVACY",
    ]
    if cell_size_meters is not None:
        lines.append(
            "Le informazioni geografiche sono rappresentate "
            f"in aree da {cell_size_meters} m."
        )
    lines.append("Percorsi precisi e luoghi esatti non sono inclusi.")
    lines.append("")

    total_move_duration = timedelta()
    total_stop_duration = timedelta()
    total_distance = 0.0
    for segment in aggregated_segments:
        if segment.kind == MobilitySegment.Kind.MOVE:
            total_move_duration += segment.duration
            total_distance += segment.distance_meters
        else:
            total_stop_duration += segment.duration

    for period_name, start_hour, end_hour in _DAY_PERIODS:
        period_segments = [
            segment
            for segment in aggregated_segments
            if _period_for_start_label(segment.start_label) == period_name
        ]
        if not period_segments:
            continue
        move = next(
            (
                segment
                for segment in period_segments
                if segment.kind == MobilitySegment.Kind.MOVE
            ),
            None,
        )
        stop = next(
            (
                segment
                for segment in period_segments
                if segment.kind == MobilitySegment.Kind.STOP
            ),
            None,
        )
        lines.extend(
            [
                f"{period_name.upper()} · {start_hour:02d}:00–{end_hour:02d}:00",
                "",
            ]
        )
        if move is not None:
            lines.extend(
                [
                    f"- Movimento: {_format_duration(move.duration)}",
                    f"- Modalità: {_activity_label_it(move.activity_label).capitalize()}",
                    f"- Distanza: {_format_distance_bucket(move.distance_meters)}",
                ]
            )
        if stop is not None:
            lines.append(f"- Tempo in sosta: {_format_duration(stop.duration)}")
        lines.append("")

    visited_area_count = sum(
        1 for segment in segments if segment.kind == MobilitySegment.Kind.STOP
    )
    lines.extend(
        [
            "TOTALE DELLA GIORNATA",
            "",
            f"- Movimento: {_format_duration(total_move_duration)}",
            f"- Tempo in sosta: {_format_duration(total_stop_duration)}",
            f"- Distanza: {_format_distance_bucket(total_distance)}",
            f"- Aree visitate: {visited_area_count}",
        ]
    )
    return "\n".join(lines)


def _segment_sentence(segments: list[DiaryExportSegment], index: int) -> str:
    segment = segments[index]
    time_range = f"{segment.start_label}-{segment.end_label}"
    duration = _format_duration(segment.duration)
    if segment.kind == MobilitySegment.Kind.MOVE:
        activity = _activity_label_it(segment.activity_label)
        from_title = _adjacent_stop_title(segments, index, step=-1)
        to_title = _adjacent_stop_title(segments, index, step=1)
        if from_title and to_title:
            description = (
                f"spostamento da {from_title} a {to_title}, "
                f"modalita' prevalente: {activity}"
            )
        else:
            description = f"spostamento, modalita' prevalente: {activity}"
        if segment.distance_meters > 0:
            description = (
                f"{description}, distanza: "
                f"{_format_distance(segment.distance_meters)}"
            )
    else:
        description = f"permanenza in {segment.title}, durata: {duration}"
    return f"{time_range}, {description}"


def _adjacent_stop_title(
    segments: list[DiaryExportSegment],
    index: int,
    *,
    step: int,
) -> str | None:
    neighbour_index = index + step
    if not 0 <= neighbour_index < len(segments):
        return None
    neighbour = segments[neighbour_index]
    return neighbour.title if neighbour.kind == MobilitySegment.Kind.STOP else None


def _activity_label_it(activity_label: str) -> str:
    return _ACTIVITY_LABELS_IT.get(activity_label, activity_label.lower())


def _prevalent_activity(segments: list[DiaryExportSegment]) -> str:
    totals: dict[str, timedelta] = {}
    for segment in segments:
        totals[segment.activity_label] = totals.get(
            segment.activity_label,
            timedelta(),
        ) + segment.duration
    if not totals:
        return "IDLE"
    return max(totals.items(), key=lambda item: item[1])[0]


def _period_for_start_label(start_label: str) -> str:
    hour = int(start_label.split(":", 1)[0])
    for name, start_hour, end_hour in _DAY_PERIODS:
        if start_hour <= hour < end_hour:
            return name
    return "notte"


def _period_timestamp(base_day: datetime, hour: int) -> datetime:
    if hour == 24:
        return base_day.replace(hour=0, minute=0, second=0, microsecond=0) + timedelta(
            days=1
        )
    return base_day.replace(hour=hour, minute=0, second=0, microsecond=0)


# Se protetto, approssimo la data di inzio di quel segmento
def _published_start(value: datetime, *, protected: bool) -> datetime:
    if not protected:
        return value
    return _floor_time(value, APPROXIMATE_TIME_GRANULARITY)

# Se protetto, approssimo la data di fine di quel segmento
def _published_end(value: datetime, *, protected: bool) -> datetime:
    if not protected:
        return value
    return _ceil_time(value, APPROXIMATE_TIME_GRANULARITY)



def _floor_time(value: datetime, step: timedelta) -> datetime:
    seconds = step.total_seconds()
    timestamp = value.timestamp()
    floored = timestamp - timestamp % seconds
    return datetime.fromtimestamp(floored, tz=value.tzinfo)


def _ceil_time(value: datetime, step: timedelta) -> datetime:
    floored = _floor_time(value, step)
    return floored if value == floored else floored + step


def _format_duration(duration: timedelta) -> str:
    total_minutes = max(0, int(round(duration.total_seconds() / 60)))
    hours, minutes = divmod(total_minutes, 60)
    if hours and minutes:
        return f"{hours} h {minutes} min"
    if hours:
        return f"{hours} h"
    return f"{minutes} min"


def _format_distance(distance_meters: float) -> str:
    if distance_meters < 1000:
        return f"{round(distance_meters)} m"
    return f"{distance_meters / 1000:.1f} km"


def _format_distance_bucket(distance_meters: float) -> str:
    if distance_meters <= 0:
        return "0 km"
    km = distance_meters / 1000
    if km < 1:
        return "Meno di 1 km"
    if km < 3:
        return "1–3 km"
    if km < 5:
        return "3–5 km"
    if km < 10:
        return "5–10 km"
    return "Oltre 10 km"
