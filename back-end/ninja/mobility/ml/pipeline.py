from __future__ import annotations

import statistics
from bisect import bisect_left
from collections import Counter
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from django.contrib.gis.geos import LineString
from django.db import connection, transaction

from ..models import ActivityLabel, MobilitySegment, Trip
from ..selectors import segments as segments_repository
from .classifier import classify_windows, _label_from_speed

STOP_STATE = "STATIONARY"
MIN_ISOLATED_LABEL_SECONDS = 60
MIN_VIRTUAL_STOP_SECONDS = 120


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
Filtra i punti GPS dentro l'intervallo [start, end). `gps_timestamps` e' la lista
dei timestamp di `gps` (stesso ordine, gia' ordinata): permette di ritagliare la
fetta con una ricerca binaria invece di riscansionare tutta la lista ad ogni chiamata.
"""
def _gps_in(gps, gps_timestamps, start: datetime, end: datetime):
    lo = bisect_left(gps_timestamps, start)
    hi = bisect_left(gps_timestamps, end)
    return gps[lo:hi]


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
    starts = [t.timestamp for t in transitions[:1]]
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

    raw = []
    cursor = start_bound
    for ev in transitions:
        if ev.timestamp > cursor:
            raw.append((cursor, ev.timestamp, state))
        state = ev.to_state
        cursor = ev.timestamp
    if end_bound > cursor:
        raw.append((cursor, end_bound, state))

    merged: list[list] = []
    for s, e, st in raw:
        kind = MobilitySegment.Kind.STOP if st == STOP_STATE else MobilitySegment.Kind.MOVE
        if merged and merged[-1][2] == kind:
            merged[-1][1] = e
        else:
            merged.append([s, e, kind])
    return merged


"""
Salva nel DB un segmento di stop.
"""
def _build_stop(trip, start, end) -> None:
    segments_repository.create_stop_segment(trip, start, end)


"""
Raggruppa elementi consecutivi che hanno la stessa label.
"""
def _label_runs(inside):
    runs = []
    current = []
    for item in inside:
        if current and item[1] != current[-1][1]:
            runs.append(current)
            current = []
        current.append(item)
    if current:
        runs.append(current)
    return runs


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
def _smooth_isolated_label_changes(inside):
    runs = _label_runs(inside)
    if len(runs) < 3:
        return inside

    smoothed = list(inside)
    cursor = 0
    for idx, run in enumerate(runs):
        run_length = len(run)
        if 0 < idx < len(runs) - 1:
            previous_label = runs[idx - 1][0][1]
            current_label = run[0][1]
            next_label = runs[idx + 1][0][1]
            if (
                previous_label == next_label
                and current_label != previous_label
                and _run_duration_seconds(run) < MIN_ISOLATED_LABEL_SECONDS
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
        for run in _label_runs(inside)
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
    label = _label_from_speed(statistics.median(speeds) if speeds else None)
    return label if label != ActivityLabel.IDLE else ActivityLabel.WALKING


"""
Salva nel DB un segmento MOVE con label, path e distanza.
"""
def _build_move_segment(trip, start, end, label, gps, gps_timestamps) -> None:
    points = _gps_in(gps, gps_timestamps, start, end)
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
def _build_move(trip, start, end, windows, labels, gps, gps_timestamps) -> None:
    inside = [
        (w, lbl)
        for w, lbl in zip(windows, labels)
        if start <= w.start_timestamp < end
    ]
    if not inside:
        points = _gps_in(gps, gps_timestamps, start, end)
        _build_move_segment(trip, start, end, _fallback_move_label(points), gps, gps_timestamps)
        return

    inside = _smooth_isolated_label_changes(inside)
    move_runs, virtual_stop_runs = _split_move_and_virtual_runs(_time_runs(inside))

    for run in virtual_stop_runs:
        _build_virtual_stop(trip, run.start_timestamp, run.end_timestamp)

    if not move_runs and not virtual_stop_runs:
        points = _gps_in(gps, gps_timestamps, start, end)
        _build_move_segment(trip, start, end, _fallback_move_label(points), gps, gps_timestamps)
        return

    for run in move_runs:
        _build_move_segment(
            trip,
            run.start_timestamp,
            run.end_timestamp,
            run.label,
            gps,
            gps_timestamps,
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
    gps_timestamps = [g.timestamp for g in gps]
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
        trip.segments.all().delete()
        trip.virtual_stop_intervals.all().delete()
        spans = _macro_spans(trip, transitions, gps, windows)
        for start, end, kind in spans:
            if kind == MobilitySegment.Kind.STOP:
                _build_stop(trip, start, end)
            else:
                _build_move(trip, start, end, windows, labels, gps, gps_timestamps)

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
