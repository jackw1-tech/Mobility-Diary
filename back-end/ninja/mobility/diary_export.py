from __future__ import annotations

from dataclasses import dataclass, replace
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

def _trip_export_segments(
    trip: Trip, *, level: str, protected: bool
) -> list[DiaryExportSegment]:
    persisted_segments = list(trip.segments.all())
    virtual_stop_intervals = list(trip.virtual_stop_intervals.all())
    gps = list(trip.gps_points.order_by("timestamp"))
    confirmed = confirmed_places_for_user(trip.user_id)
    return [
        _export_segment(segment, stop_details, level=level, protected=protected)
        for segment, stop_details in project_diary_with_places(
            persisted_segments, virtual_stop_intervals, gps, confirmed
        )
    ]


def _build_privacy_export(
    *,
    trip_id: int,
    level: str,
    protected: bool,
    cell_size_meters: int | None,
    segments: list[DiaryExportSegment],
) -> DiaryPrivacyExport:
    return DiaryPrivacyExport(
        trip_id=trip_id,
        level=level,
        protected=protected,
        approximated_coordinates=cell_size_meters is not None,
        cell_size_meters=cell_size_meters,
        text=_export_text(
            trip_id=trip_id,
            level=level,
            protected=protected,
            cell_size_meters=cell_size_meters,
            segments=segments,
        ),
        segments=segments,
    )


# costruzione diario con livello di privacy impostato, per un singolo viaggio
def build_trip_privacy_export(trip: Trip, *, level: str) -> DiaryPrivacyExport:
    cell_size_meters = privacy_cell_size_meters(level)
    protected = level != UserPrivacySettings.Level.PRECISE
    segments = _trip_export_segments(trip, level=level, protected=protected)
    return _build_privacy_export(
        trip_id=trip.id,
        level=level,
        protected=protected,
        cell_size_meters=cell_size_meters,
        segments=segments,
    )


# costruzione diario con livello di privacy impostato, per l'intera giornata
def build_day_privacy_export(
    trips: list[Trip], *, trip_id: int, level: str
) -> DiaryPrivacyExport:
    cell_size_meters = privacy_cell_size_meters(level)
    protected = level != UserPrivacySettings.Level.PRECISE
    segments = sorted(
        (
            segment
            for trip in trips
            for segment in _trip_export_segments(trip, level=level, protected=protected)
        ),
        key=lambda segment: segment.start_timestamp,
    )
    return _build_privacy_export(
        trip_id=trip_id,
        level=level,
        protected=protected,
        cell_size_meters=cell_size_meters,
        segments=segments,
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
        title=_segment_title(segment, stop_details, level=level),
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

def _segment_title(
    segment: ProjectedDiarySegment,
    stop_details: VisibleStopDetails | None,
    *,
    level: str,
) -> str:
    if segment.kind == MobilitySegment.Kind.MOVE:
        return _activity_label_it(segment.activity_label)

    place = None if stop_details is None else stop_details.matched_place
    # Il nome reale del luogo resta visibile per precise e approximate (li'
    # la privacy sulla posizione la fa gia' il cloaking spaziale delle
    # coordinate); solo aggregated maschera anche il nome, mostrando solo la
    # categoria generica del luogo.
    if level != UserPrivacySettings.Level.AGGREGATED:
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
    readable_segments = _merge_overlapping_segments(segments)
    for index, segment in enumerate(readable_segments):
        lines.append(_segment_sentence(readable_segments, index))
    return "\n".join(lines)


def _segment_merge_key(segment: DiaryExportSegment) -> tuple:
    if segment.kind == MobilitySegment.Kind.MOVE:
        return (segment.kind, segment.activity_label)
    return (segment.kind, segment.title)


# Accorpa segmenti consecutivi/sovrapposti con la stessa modalita' (MOVE) o
# lo stesso luogo (STOP): la classificazione HAR puo' "sfarfallare" su
# intervalli brevi generando tanti micro-segmenti che si accavallano nel
# tempo (es. veicolo/a piedi/veicolo nello stesso minuto) - qui vengono
# fusi solo per la resa testuale, senza toccare i segmenti originali (che
# restano quelli usati per i dati strutturati esportati/serviti dalle API).
def _merge_overlapping_segments(
    segments: list[DiaryExportSegment],
) -> list[DiaryExportSegment]:
    if not segments:
        return []
    ordered = sorted(segments, key=lambda segment: segment.start_timestamp)
    merged: list[DiaryExportSegment] = [ordered[0]]
    for segment in ordered[1:]:
        last = merged[-1]
        touches_or_overlaps = segment.start_timestamp <= last.end_timestamp
        if touches_or_overlaps and _segment_merge_key(segment) == _segment_merge_key(last):
            new_end = max(last.end_timestamp, segment.end_timestamp)
            merged[-1] = replace(
                last,
                end_timestamp=new_end,
                end_label=new_end.strftime("%H:%M"),
                duration=last.duration + segment.duration,
                distance_meters=last.distance_meters + segment.distance_meters,
                point_count=last.point_count + segment.point_count,
                coordinates=last.coordinates + segment.coordinates,
            )
        else:
            merged.append(segment)
    return merged

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
