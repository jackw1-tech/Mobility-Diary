from __future__ import annotations

from dataclasses import dataclass, replace
from datetime import datetime

from django.contrib.gis.geos import LineString

from .models import ActivityLabel, MobilitySegment


@dataclass(frozen=True)
class ProjectedDiarySegment:
    kind: str
    start_timestamp: datetime
    end_timestamp: datetime
    activity_label: str
    distance_meters: float
    path: LineString | None


def project_diary_segments(
    segments: list[MobilitySegment],
) -> list[ProjectedDiarySegment]:
    """Collapse adjacent stop-like stretches for read-time diary consumers.

    Place semantics are applied as a read-time overlay by the diary endpoint, not
    here: this projection only normalizes stop/move structure.
    """

    ordered = sorted(
        segments,
        key=lambda segment: (
            segment.start_timestamp,
            segment.end_timestamp,
            segment.pk or 0,
        ),
    )
    projected: list[ProjectedDiarySegment] = []
    pending_stop: ProjectedDiarySegment | None = None

    for segment in ordered:
        if _is_stop_like(segment):
            stop_projection = _as_stop_projection(segment)
            if pending_stop is None:
                pending_stop = stop_projection
                continue
            if stop_projection.start_timestamp <= pending_stop.end_timestamp:
                pending_stop = replace(
                    pending_stop,
                    end_timestamp=max(
                        pending_stop.end_timestamp,
                        stop_projection.end_timestamp,
                    ),
                )
                continue
            projected.append(pending_stop)
            pending_stop = stop_projection
            continue

        if pending_stop is not None:
            projected.append(pending_stop)
            pending_stop = None
        projected.append(
            ProjectedDiarySegment(
                kind=segment.kind,
                start_timestamp=segment.start_timestamp,
                end_timestamp=segment.end_timestamp,
                activity_label=segment.activity_label,
                distance_meters=segment.distance_meters,
                path=segment.path,
            )
        )

    if pending_stop is not None:
        projected.append(pending_stop)

    return projected


def _is_stop_like(segment: MobilitySegment) -> bool:
    return (
        segment.kind == MobilitySegment.Kind.STOP
        or segment.activity_label == ActivityLabel.IDLE
    )


def _as_stop_projection(segment: MobilitySegment) -> ProjectedDiarySegment:
    return ProjectedDiarySegment(
        kind=MobilitySegment.Kind.STOP,
        start_timestamp=segment.start_timestamp,
        end_timestamp=segment.end_timestamp,
        activity_label=ActivityLabel.IDLE,
        distance_meters=0.0,
        path=None,
    )
