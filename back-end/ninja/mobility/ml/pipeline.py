from __future__ import annotations

import statistics
from collections import Counter
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from django.contrib.gis.geos import LineString
from django.db import connection, transaction

from ..models import ActivityLabel, MobilitySegment, Trip
from ..selectors import segments as segments_repository
from .classifier import WALK_MAX, classify_windows, _label_from_speed

STOP_STATE = "STATIONARY"
MIN_ISOLATED_LABEL_SECONDS = 60
MIN_VIRTUAL_STOP_SECONDS = 110 #Valore leggermente meno dei 120 di stationaryEvidenceRequired


@dataclass(frozen=True)
class PipelineSensorWindow:
    start_timestamp: datetime
    end_timestamp: datetime
    sample_count: int
    frequency_hz: int
    matrix: Any


@dataclass(frozen=True)
class LabelTimeRun:
    start_timestamp: datetime
    end_timestamp: datetime
    label: str


"""
Filtra i punti GPS dentro l'intervallo [start, end) della macro
"""
def _gps_in(gps, start: datetime, end: datetime):
    return [p for p in gps if start <= p.timestamp < end]


"""
Calcola la distanza reale (in metri) della LineString del segmento, delegando
il calcolo geodetico a PostGIS (ST_Length su geography).
"""
def _path_distance(path: LineString | None) -> float:
    if path is None:
        return 0.0
    with connection.cursor() as cursor:
        cursor.execute("SELECT ST_Length(%s::geography)", [path.ewkt])
        return cursor.fetchone()[0]


"""
Crea la LineString del segmento dai punti GPS, se ci sono almeno due coordinate.
Considera però solo i punti di quello specifico segmento
Questo porta ad avere una differenza di punti nella mappa traccia e quella in segmenti nel front end
La mappa traccia mostra tutti i punti del gps, la mappa segmenti solo i punti gps attribuiti ad un movimento
"""
def _segment_path(points):
    coords = [(p.point.x, p.point.y) for p in points]
    if len(set(coords)) < 2:
        return None
    return LineString(coords, srid=4326)


"""
Costruisce i macro-intervalli STOP/MOVE usando transizioni, GPS e finestre HAR.
"""
def _macro_spans(trip, transitions, gps, windows):
    #Calcolo estremo iniziale e finale di ogni viaggio
    starts = [transitions[0].timestamp] if transitions else []
    starts += [gps[0].timestamp] if gps else []
    starts += [windows[0].start_timestamp] if windows else []
    ends = [transitions[-1].timestamp] if transitions else []
    ends += [gps[-1].timestamp] if gps else []
    ends += [windows[-1].end_timestamp] if windows else []
    if trip.ended_at:
        ends.append(trip.ended_at)

    if not starts or not ends:
        return []

    start_bound = min(starts)
    end_bound = max(ends)
    state = transitions[0].from_state if transitions else STOP_STATE

    # associo ad ogni transition / taglio un inizio e una fine
    # un singlo taglio è la fine di un segmento e l'inizio di un altro 
    raw = []
    cursor = start_bound
    for event in transitions:
        if event.timestamp > cursor:
            raw.append((cursor, event.timestamp, state)) #inizio, fine, stato
        state = event.to_state
        cursor = event.timestamp
    if end_bound > cursor:
        raw.append((cursor, end_bound, state))

    return [
        [s, e, MobilitySegment.Kind.STOP if st == STOP_STATE else MobilitySegment.Kind.MOVE]
        for s, e, st in raw
    ]


"""
Salva nel DB un segmento di stop.
"""
def _build_stop(trip, start, end) -> None:
    segments_repository.create_stop_segment(trip, start, end)


"""
Raggruppa elementi consecutivi che hanno la stessa label.
-> lista di liste di label consecutive
"""
def _label_group_by(inside):
    group = []
    current = []
    for item in inside:
        if current and item[1] != current[-1][1]:
            group.append(current)
            current = []
        current.append(item)
    if current:
        group.append(current)
    return group


"""
Calcola la durata in secondi di un run/blocco.
"""
def _run_duration_seconds(run) -> float:
    if isinstance(run, LabelTimeRun):
        return (run.end_timestamp - run.start_timestamp).total_seconds()
    return (run[-1][0].end_timestamp - run[0][0].start_timestamp).total_seconds()


"""
Corregge cambi di label brevi e isolati tra due blocchi uguali.
"""
def _isolated_label_changes(inside):
    groups_by_label = _label_group_by(inside)
    #Se ci sono solo due grippi di label consecutive -> non c'è nulla da correggere
    if len(groups_by_label) < 3:
        return inside

    smoothed = list(inside)
    cursor = 0
    for idx, groups in enumerate(groups_by_label):
        run_length = len(groups)
        if 0 < idx < len(groups_by_label) - 1:
            previous_label = groups_by_label[idx - 1][0][1]
            current_label = groups[0][1]
            next_label = groups_by_label[idx + 1][0][1]
            if (
                previous_label == next_label
                and current_label != previous_label
                and _run_duration_seconds(groups) < MIN_ISOLATED_LABEL_SECONDS
            ):
                for offset in range(run_length):
                    window, _label = smoothed[cursor + offset]
                    smoothed[cursor + offset] = (window, previous_label)
        cursor += run_length
    return smoothed


"""
Trasforma run di finestre in intervalli temporali con una singola label.
"""
def _time_runs(inside) -> list[LabelTimeRun]:
    return [
        LabelTimeRun(
            start_timestamp=run[0][0].start_timestamp,
            end_timestamp=run[-1][0].end_timestamp,
            label=run[0][1],
        )
        for run in _label_group_by(inside)
    ]


"""
Unisce run adiacenti se hanno la stessa label e sono contigui nel tempo.
"""
def _merge_adjacent_runs(runs: list[LabelTimeRun]) -> list[LabelTimeRun]:
    merged: list[LabelTimeRun] = []
    for run in runs:
        if (
            merged
            and merged[-1].label == run.label
            and merged[-1].end_timestamp == run.start_timestamp
        ):
            merged[-1] = LabelTimeRun(
                start_timestamp=merged[-1].start_timestamp,
                end_timestamp=run.end_timestamp,
                label=run.label,
            )
            continue
        merged.append(run)
    return merged


"""
Decide con quale label sostituire un IDLE breve dentro un movimento.
"""
def _target_label_for_short_idle(
    runs: list[LabelTimeRun],
    index: int,
    resolved: list[LabelTimeRun],
) -> str | None:
    if resolved:
        return resolved[-1].label
    for following in runs[index + 1 :]:
        if following.label != ActivityLabel.IDLE:
            return following.label
    return None


"""
Separa i run di movimento dagli IDLE lunghi, che diventano virtual stop.
"""
def _split_move_and_virtual_runs(
    runs: list[LabelTimeRun],
) -> tuple[list[LabelTimeRun], list[LabelTimeRun]]:
    move_runs: list[LabelTimeRun] = []
    virtual_stop_runs: list[LabelTimeRun] = []

    for index, run in enumerate(runs):
        if run.label != ActivityLabel.IDLE:
            move_runs.append(run)
            continue
        
        #Cerco di evitare previsioni da rumore
        if _run_duration_seconds(run) >= MIN_VIRTUAL_STOP_SECONDS:
            virtual_stop_runs.append(run)
            continue

        target_label = _target_label_for_short_idle(runs, index, move_runs)
        if target_label is None:
            continue
        move_runs.append(
            LabelTimeRun(
                start_timestamp=run.start_timestamp,
                end_timestamp=run.end_timestamp,
                label=target_label,
            )
        )

    return _merge_adjacent_runs(move_runs), virtual_stop_runs


"""
Salva nel DB una pausa virtuale rilevata dentro un macro-movimento.
"""
def _build_virtual_stop(trip, start, end) -> None:
    segments_repository.create_virtual_stop(trip, start, end)


"""
Stima una label di movimento di ripiego usando la velocita GPS.
"""
def _fallback_move_label(points) -> str:
    speeds = [p.speed_mps for p in points if p.speed_mps is not None]
    if not speeds:
        return ActivityLabel.WALKING
    return _label_from_speed(statistics.median(speeds))


"""
Corregge un'etichetta MOVING_VEHICLE del classificatore se la velocita GPS del
segmento e' incompatibile
"""
def _sanity_check_vehicle_label(label: str, points) -> str:
    if label != ActivityLabel.MOVING_VEHICLE:
        return label
    speeds = [p.speed_mps for p in points if p.speed_mps is not None]
    if not speeds:
        return label
    median_speed = statistics.median(speeds)
    if median_speed >= WALK_MAX:
        return label
    return _label_from_speed(median_speed)


"""
Salva nel DB un segmento MOVE con label, path e distanza.
"""
def _build_move_segment(trip, start, end, label, gps) -> None:
    points = _gps_in(gps, start, end)
    label = _sanity_check_vehicle_label(label, points)
    path = _segment_path(points)
    segments_repository.create_move_segment(
        trip,
        start=start,
        end=end,
        label=label,
        path=path,
        distance_meters=_path_distance(path),
    )


"""
Spezza un macro MOVE in segmenti HAR e virtual stop.
"""
def _build_move(trip, start, end, windows, labels, gps) -> None:
    #Filtro etichette e label che riguardano questa specifica macro
    inside = [
        (w, lbl)
        for w, lbl in zip(windows, labels)
        if start <= w.start_timestamp < end
    ]
    #Nel caso non ci fossero dati har per questa macro (quando il telefono va in background ma la fsm era movement) 
    #Uso la mediana delle velocità fornite dal gps come fall back
    if not inside:
        points = _gps_in(gps, start, end)
        _build_move_segment(trip, start, end, _fallback_move_label(points), gps)
        return

    inside = _isolated_label_changes(inside)
    move_runs, virtual_stop_runs = _split_move_and_virtual_runs(_time_runs(inside))

    for run in virtual_stop_runs:
        _build_virtual_stop(trip, run.start_timestamp, run.end_timestamp)

    # I dati dei sensori ci sono ma _isolated_label_changes ha reso l'intero macro tutta idle 
    # ma dura meno di MIN_VIRTUAL_STOP_SECONDS -> virtual e move vuoti -> fall back come se i dati har non ci fossero 
    if not move_runs and not virtual_stop_runs:
        points = _gps_in(gps, start, end)
        _build_move_segment(trip, start, end, _fallback_move_label(points), gps)
        return

    for run in move_runs:
        _build_move_segment(
            trip,
            run.start_timestamp,
            run.end_timestamp,
            run.label,
            gps,
        )


"""
Esegue tutta la pipeline: classifica, ricrea segmenti e marca il trip processato.
"""
def run_pipeline(
    trip: Trip,
    *,
    sensor_windows: list[PipelineSensorWindow] | None = None,
) -> dict:
    windows = sorted(sensor_windows or [], key=lambda window: window.start_timestamp)
    gps = list(trip.gps_points.order_by("timestamp"))
    transitions = list(trip.state_transitions.order_by("timestamp"))

    all_windows_have_matrix = all(w.matrix is not None for w in windows)

    classification = classify_windows(
        raw_windows=windows if all_windows_have_matrix else None,
    )

    labels = classification.labels

    classifier_summary = {
        **classification.summary,
        "final_label_distribution": dict(Counter(labels)),
    }

    #diario
    with transaction.atomic():
        # stesso pattern del gps mining, in caso di retry, prima elimino quello già fatto e poi reinserisco tuttod
        trip.segments.all().delete()
        trip.virtual_stop_intervals.all().delete()
        spans = _macro_spans(trip, transitions, gps, windows)
        for start, end, kind in spans:
            if kind == MobilitySegment.Kind.STOP:
                _build_stop(trip, start, end)
            else:
                _build_move(trip, start, end, windows, labels, gps)

        trip.status = Trip.Status.PROCESSED
        trip.save(update_fields=["status", "updated_at"])

    segment_count = trip.segments.count()
    virtual_stop_count = trip.virtual_stop_intervals.count()

    result = {
        "windows": len(windows),
        "gps_points": len(gps),
        "transitions": len(transitions),
        "segments": segment_count,
        "virtual_stop_intervals": virtual_stop_count,
        **classifier_summary,
    }
    return result
