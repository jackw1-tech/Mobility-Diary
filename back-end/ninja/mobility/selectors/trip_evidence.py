"""Repository di materializzazione dell'evidenza core di un Trip."""

from __future__ import annotations

from dataclasses import dataclass

from ..models import GpsPoint, StateTransition, Trip


@dataclass(frozen=True)
class TripEvidenceCounts:
    gps_points: int
    state_transitions: int


def evidence_counts(trip: Trip) -> TripEvidenceCounts:
    return TripEvidenceCounts(
        gps_points=GpsPoint.objects.filter(trip=trip).count(),
        state_transitions=StateTransition.objects.filter(trip=trip).count(),
    )


def ordered_gps_coordinates(trip: Trip):
    return (
        GpsPoint.objects.filter(trip=trip)
        .order_by("timestamp", "id")
        .values_list("point", flat=True)
    )


def bulk_create_gps_points(rows: list[GpsPoint]) -> None:
    GpsPoint.objects.bulk_create(rows, ignore_conflicts=True)


def bulk_create_state_transitions(rows: list[StateTransition]) -> None:
    StateTransition.objects.bulk_create(rows, ignore_conflicts=True)
