from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta

from django.contrib.gis.geos import LineString

from .models import ActivityLabel, MobilitySegment, VirtualStopInterval

# Due intervalli stop-like separati da vengono fusi
STOP_GAP_TOLERANCE = timedelta(minutes=2)


@dataclass(frozen=True)
class ProjectedDiarySegment:
    kind: str
    start_timestamp: datetime
    end_timestamp: datetime
    activity_label: str
    distance_meters: float
    path: LineString | None


@dataclass(frozen=True)
class _StopLikeInterval:
    start_timestamp: datetime
    end_timestamp: datetime

"""Riordina i segmenti e fonde gli intervalli di sosta
Restituisce una lista di ProjectedDiarySegment che possono essere movimenti o soste
"""
def project_diary_segments(
    segments: list[MobilitySegment],
    virtual_stop_intervals: list[VirtualStopInterval] | None = None,
) -> list[ProjectedDiarySegment]:
    ordered_segments = sorted(
        segments,
        key=lambda segment: (
            segment.start_timestamp,
            segment.end_timestamp,
            segment.pk or 0,
        ),
    )
    moves = [
        ProjectedDiarySegment(
            kind=segment.kind,
            start_timestamp=segment.start_timestamp,
            end_timestamp=segment.end_timestamp,
            activity_label=segment.activity_label,
            distance_meters=segment.distance_meters,
            path=segment.path,
        )
        for segment in ordered_segments
        if not _is_stop_like(segment)
    ]
    stops = _merge_stop_like_intervals(
        _collect_stop_like_intervals(
            ordered_segments,
            virtual_stop_intervals or [],
        )
    )
    return sorted(
        [*moves, *stops],
        key=lambda segment: (
            segment.start_timestamp,
            segment.end_timestamp,
            segment.kind,
        ),
    )

"""Valuta se un segmento è di Stop"""
def _is_stop_like(segment: MobilitySegment) -> bool:
    return (
        segment.kind == MobilitySegment.Kind.STOP
        or segment.activity_label == ActivityLabel.IDLE
    )

"""Prende due liste di elementi diversi ma con start e stop come attributi comune -> _StopLikeInterval """
def _collect_stop_like_intervals(
    segments: list[MobilitySegment],
    virtual_stop_intervals: list[VirtualStopInterval],
) -> list[_StopLikeInterval]:
    intervals = [
        _StopLikeInterval(
            start_timestamp=segment.start_timestamp,
            end_timestamp=segment.end_timestamp,
        )
        for segment in segments
        if _is_stop_like(segment)
    ]
    intervals.extend(
        _StopLikeInterval(
            start_timestamp=interval.start_timestamp,
            end_timestamp=interval.end_timestamp,
        )
        for interval in virtual_stop_intervals
    )
    return sorted(
        intervals,
        key=lambda interval: (interval.start_timestamp, interval.end_timestamp),
    )

"""Unisce i segmenti di stop e i virtual stop intervals
"""
def _merge_stop_like_intervals(
    intervals: list[_StopLikeInterval],
) -> list[ProjectedDiarySegment]:
    if not intervals:
        return []
    #lista di liste di due elementi
    merged: list[list[datetime]] = []
    for interval in intervals:
        if (
            not merged
            or interval.start_timestamp > merged[-1][1] + STOP_GAP_TOLERANCE
        ):
            merged.append([interval.start_timestamp, interval.end_timestamp])
            continue
        merged[-1][1] = max(merged[-1][1], interval.end_timestamp)

    return [
        ProjectedDiarySegment(
            kind=MobilitySegment.Kind.STOP,
            start_timestamp=start,
            end_timestamp=end,
            activity_label=ActivityLabel.IDLE,
            distance_meters=0.0,
            path=None,
        )
        for start, end in merged
    ]
