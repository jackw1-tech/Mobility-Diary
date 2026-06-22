"""Pipeline di elaborazione di un viaggio: da dati grezzi a diario.

Passi (a fine viaggio, nel worker Celery):
  1. normalizzazione reale delle finestre (grezzo -> pronto per il modello)
  2. velocita GPS per finestra (contesto temporale)
  3. classificazione attivita (placeholder GPS; sostituibile con CNN+GRU)
  4. fusione GPS per IDLE<->MOVING_VEHICLE
  5. segmentazione a 2 passate:
       passata 1: confini SOSTA/SPOSTAMENTO dalle transizioni FSM
       passata 2: dentro gli SPOSTAMENTI, split a ogni cambio di label HAR
  6. luoghi significativi (sosta >= soglia): centroide + raggio + dwell
  7. scrittura MobilitySegment + SignificantPlace, Trip.status = PROCESSED
"""

from __future__ import annotations

import math
import statistics
from collections import Counter
from dataclasses import dataclass
from datetime import datetime

from django.contrib.gis.geos import LineString, Point

from ..models import ActivityLabel, MobilitySegment, SignificantPlace, Trip
from .classifier import classify_windows, correct_idle_with_gps, _label_from_speed
from .preprocessing import normalize_window

STOP_STATE = "STATIONARY"
SIGNIFICANT_DWELL_SECONDS = 5 * 60  # soglia "permanenza" (motivata in relazione)


@dataclass(frozen=True)
class PipelineSensorWindow:
    start_timestamp: datetime
    end_timestamp: datetime
    sample_count: int
    frequency_hz: int
    matrix: list[list[float]]


def _haversine(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(min(1.0, math.sqrt(a)))


def _gps_in(gps, start: datetime, end: datetime):
    return [g for g in gps if start <= g.timestamp < end]


def _window_speed(window, gps) -> float | None:
    speeds = [
        g.speed_mps
        for g in gps
        if window.start_timestamp <= g.timestamp < window.end_timestamp
    ]
    return statistics.median(speeds) if speeds else None


def _centroid(points) -> tuple[float, float]:
    lat = statistics.fmean(p.point.y for p in points)
    lon = statistics.fmean(p.point.x for p in points)
    return lat, lon


def _path_distance(points) -> float:
    total = 0.0
    for a, b in zip(points, points[1:]):
        total += _haversine(a.point.y, a.point.x, b.point.y, b.point.x)
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


def _build_stop(trip, start, end, gps) -> None:
    dwell = (end - start).total_seconds()
    points = _gps_in(gps, start, end)
    place = None
    if dwell >= SIGNIFICANT_DWELL_SECONDS and points:
        lat, lon = _centroid(points)
        radius = max(
            (_haversine(lat, lon, p.point.y, p.point.x) for p in points), default=0.0
        )
        place = SignificantPlace.objects.create(
            trip=trip,
            center=Point(lon, lat, srid=4326),
            radius_meters=radius,
            dwell_seconds=int(dwell),
        )
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.STOP,
        start_timestamp=start,
        end_timestamp=end,
        activity_label=ActivityLabel.IDLE,
        place=place,
        path=None,
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
        speeds = [p.speed_mps for p in points]
        label = _label_from_speed(statistics.median(speeds) if speeds else None)
        MobilitySegment.objects.create(
            trip=trip,
            kind=MobilitySegment.Kind.MOVE,
            start_timestamp=start,
            end_timestamp=end,
            activity_label=label,
            path=_segment_path(points),
            distance_meters=_path_distance(points),
        )
        return

    # Passata 2: split a ogni cambio di label.
    group_start_idx = 0
    for i in range(1, len(inside) + 1):
        if i == len(inside) or inside[i][1] != inside[group_start_idx][1]:
            group = inside[group_start_idx:i]
            seg_start = group[0][0].start_timestamp
            seg_end = group[-1][0].end_timestamp
            label = group[0][1]
            points = _gps_in(gps, seg_start, seg_end)
            MobilitySegment.objects.create(
                trip=trip,
                kind=MobilitySegment.Kind.MOVE,
                start_timestamp=seg_start,
                end_timestamp=seg_end,
                activity_label=label,
                path=_segment_path(points),
                distance_meters=_path_distance(points),
            )
            group_start_idx = i


def run_pipeline(
    trip: Trip,
    *,
    sensor_windows: list[PipelineSensorWindow] | None = None,
) -> dict:
    windows = (
        list(trip.sensor_windows.order_by("start_timestamp"))
        if sensor_windows is None
        else sorted(sensor_windows, key=lambda window: window.start_timestamp)
    )
    gps = list(trip.gps_points.order_by("timestamp"))
    transitions = list(trip.state_transitions.order_by("timestamp"))

    # 1. normalizzazione reale (grezzo -> pronto). Per ora il risultato non
    #    alimenta ancora un modello: il classificatore e un placeholder.
    all_windows_have_matrix = all(w.matrix is not None for w in windows)
    _normalized = [
        normalize_window(w.matrix) for w in windows if w.matrix is not None
    ]

    # 2-4. velocita per finestra, classificazione, fusione GPS.
    win_speed = [_window_speed(w, gps) for w in windows]
    classification = classify_windows(
        _normalized,
        win_speed,
        raw_windows=windows if all_windows_have_matrix else None,
    )
    labels = classification.labels
    labels = correct_idle_with_gps(labels, win_speed)
    classifier_summary = {
        **classification.summary,
        "final_label_distribution": dict(Counter(labels)),
    }

    # Riscrittura idempotente del diario.
    trip.segments.all().delete()
    trip.significant_places.all().delete()

    # 5-7. segmentazione + luoghi + scrittura.
    spans = _macro_spans(trip, transitions, gps, windows)
    for start, end, kind in spans:
        if kind == MobilitySegment.Kind.STOP:
            _build_stop(trip, start, end, gps)
        else:
            _build_move(trip, start, end, windows, labels, gps)

    trip.status = Trip.Status.PROCESSED
    trip.save(update_fields=["status", "updated_at"])

    return {
        "windows": len(windows),
        "gps_points": len(gps),
        "transitions": len(transitions),
        "segments": trip.segments.count(),
        "significant_places": trip.significant_places.count(),
        **classifier_summary,
    }
