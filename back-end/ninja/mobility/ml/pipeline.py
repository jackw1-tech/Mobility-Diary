"""Pipeline di elaborazione di un viaggio: da dati grezzi a diario.

Passi (a fine viaggio, nel worker Celery):
  1. normalizzazione reale delle finestre (grezzo -> pronto per il modello)
  2. velocita GPS per finestra (contesto temporale)
  3. classificazione attivita (CNN+GRU quando i raw sono disponibili; fallback GPS)
  4. fusione GPS per IDLE<->MOVING_VEHICLE
  5. segmentazione a 2 passate:
       passata 1: confini SOSTA/SPOSTAMENTO dalle transizioni FSM
       passata 2: dentro gli SPOSTAMENTI, smoothing e split dei cambi label HAR
  6. scrittura MobilitySegment, Trip.status = PROCESSED

I luoghi significativi non nascono piu' qui: la scoperta e' user-scoped e parte
dai GpsPoint grezzi dopo l'arricchimento finale (vedi ADR 0029).
"""

from __future__ import annotations

import statistics
import time
from collections import Counter
from dataclasses import dataclass
from datetime import datetime
from typing import Any

from django.contrib.gis.geos import LineString
from django.db import transaction

from ..geo import haversine_meters
from ..models import ActivityLabel, MobilitySegment, Trip, VirtualStopInterval
from .classifier import classify_windows, correct_idle_with_gps, _label_from_speed
from .preprocessing import normalize_window

STOP_STATE = "STATIONARY"
MIN_ISOLATED_LABEL_SECONDS = 60
MIN_VIRTUAL_STOP_SECONDS = 120


def _add_elapsed_ms(timings: dict[str, Any] | None, key: str, start: float) -> None:
    if timings is None:
        return
    elapsed = (time.perf_counter() - start) * 1000
    timings[key] = round(float(timings.get(key, 0.0)) + elapsed, 2)


@dataclass(frozen=True)
class PipelineSensorWindow:
    start_timestamp: datetime
    end_timestamp: datetime
    sample_count: int
    frequency_hz: int
    matrix: list[list[float]]


@dataclass(frozen=True)
class LabelTimeRun:
    start_timestamp: datetime
    end_timestamp: datetime
    label: str


def _gps_in(gps, start: datetime, end: datetime):
    return [g for g in gps if start <= g.timestamp < end]


def _window_speed(window, gps) -> float | None:
    speeds = [
        g.speed_mps
        for g in gps
        if window.start_timestamp <= g.timestamp < window.end_timestamp
    ]
    return statistics.median(speeds) if speeds else None


def _path_distance(points) -> float:
    total = 0.0
    for a, b in zip(points, points[1:]):
        total += haversine_meters(a.point.y, a.point.x, b.point.y, b.point.x)
    return total


def _segment_path(points):
    coords = [(p.point.x, p.point.y) for p in points]
    if len(set(coords)) < 2:
        return None
    return LineString(coords, srid=4326)


def _macro_spans(trip, transitions, gps, windows):
    """Passata 1: spans (start, end, kind) alternati SOSTA/SPOSTAMENTO."""
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


def _build_stop(trip, start, end) -> None:
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.STOP,
        start_timestamp=start,
        end_timestamp=end,
        activity_label=ActivityLabel.IDLE,
        path=None,
    )


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


def _run_duration_seconds(run) -> float:
    if isinstance(run, LabelTimeRun):
        return (run.end_timestamp - run.start_timestamp).total_seconds()
    return (run[-1][0].end_timestamp - run[0][0].start_timestamp).total_seconds()


def _smooth_isolated_label_changes(inside):
    """Fonde label brevissime isolate tra due blocchi con la stessa label."""
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


def _time_runs(inside) -> list[LabelTimeRun]:
    return [
        LabelTimeRun(
            start_timestamp=run[0][0].start_timestamp,
            end_timestamp=run[-1][0].end_timestamp,
            label=run[0][1],
        )
        for run in _label_runs(inside)
    ]


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


def _build_virtual_stop(trip, start, end) -> None:
    VirtualStopInterval.objects.create(
        trip=trip,
        start_timestamp=start,
        end_timestamp=end,
    )


def _fallback_move_label(points) -> str:
    speeds = [p.speed_mps for p in points]
    label = _label_from_speed(statistics.median(speeds) if speeds else None)
    return label if label != ActivityLabel.IDLE else ActivityLabel.WALKING


def _build_move_segment(trip, start, end, label, gps) -> None:
    points = _gps_in(gps, start, end)
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.MOVE,
        start_timestamp=start,
        end_timestamp=end,
        activity_label=label,
        path=_segment_path(points),
        distance_meters=_path_distance(points),
    )


def _build_move(trip, start, end, windows, labels, gps) -> None:
    inside = [
        (w, lbl)
        for w, lbl in zip(windows, labels)
        if start <= w.start_timestamp < end
    ]
    if not inside:
        # Spostamento senza finestre inerziali: ripiego sulla velocita GPS.
        points = _gps_in(gps, start, end)
        _build_move_segment(trip, start, end, _fallback_move_label(points), gps)
        return

    inside = _smooth_isolated_label_changes(inside)
    move_runs, virtual_stop_runs = _split_move_and_virtual_runs(_time_runs(inside))

    for run in virtual_stop_runs:
        _build_virtual_stop(trip, run.start_timestamp, run.end_timestamp)

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


def run_pipeline(
    trip: Trip,
    *,
    sensor_windows: list[PipelineSensorWindow] | None = None,
    timings: dict[str, Any] | None = None,
) -> dict:
    pipeline_start = time.perf_counter()

    load_inputs_start = time.perf_counter()
    windows = (
        list(trip.sensor_windows.order_by("start_timestamp"))
        if sensor_windows is None
        else sorted(sensor_windows, key=lambda window: window.start_timestamp)
    )
    gps = list(trip.gps_points.order_by("timestamp"))
    transitions = list(trip.state_transitions.order_by("timestamp"))
    _add_elapsed_ms(timings, "pipeline_load_inputs_ms", load_inputs_start)

    # 1. normalizzazione reale (grezzo -> pronto per il modello/fallback).
    normalize_start = time.perf_counter()
    all_windows_have_matrix = all(w.matrix is not None for w in windows)
    _normalized = [
        normalize_window(w.matrix) for w in windows if w.matrix is not None
    ]
    _add_elapsed_ms(timings, "pipeline_normalize_ms", normalize_start)

    # 2-4. velocita per finestra, classificazione, fusione GPS.
    speed_start = time.perf_counter()
    win_speed = [_window_speed(w, gps) for w in windows]
    _add_elapsed_ms(timings, "pipeline_window_speed_ms", speed_start)

    classify_start = time.perf_counter()
    classification = classify_windows(
        _normalized,
        win_speed,
        raw_windows=windows if all_windows_have_matrix else None,
    )
    _add_elapsed_ms(timings, "pipeline_classify_ms", classify_start)

    correction_start = time.perf_counter()
    labels = classification.labels
    labels = correct_idle_with_gps(labels, win_speed)
    _add_elapsed_ms(timings, "pipeline_gps_correction_ms", correction_start)

    classifier_summary = {
        **classification.summary,
        "final_label_distribution": dict(Counter(labels)),
    }

    segment_start = time.perf_counter()
    with transaction.atomic():
        # Riscrittura idempotente del diario.
        trip.segments.all().delete()
        trip.virtual_stop_intervals.all().delete()

        # 5-6. segmentazione + scrittura.
        spans = _macro_spans(trip, transitions, gps, windows)
        for start, end, kind in spans:
            if kind == MobilitySegment.Kind.STOP:
                _build_stop(trip, start, end)
            else:
                _build_move(trip, start, end, windows, labels, gps)

        trip.status = Trip.Status.PROCESSED
        trip.save(update_fields=["status", "updated_at"])
    _add_elapsed_ms(timings, "pipeline_segment_db_ms", segment_start)

    counts_start = time.perf_counter()
    result = {
        "windows": len(windows),
        "gps_points": len(gps),
        "transitions": len(transitions),
        "segments": trip.segments.count(),
        "virtual_stop_intervals": trip.virtual_stop_intervals.count(),
        **classifier_summary,
    }
    _add_elapsed_ms(timings, "pipeline_result_counts_ms", counts_start)
    _add_elapsed_ms(timings, "pipeline_total_ms", pipeline_start)
    return result
