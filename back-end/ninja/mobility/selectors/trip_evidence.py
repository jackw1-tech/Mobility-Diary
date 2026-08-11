"""Repository dell'evidenza core di un Trip (GpsPoint, StateTransition).

Unico punto del progetto in cui compaiono `GpsPoint.objects` e
`StateTransition.objects`. Prima della sua introduzione, il conteggio e
l'inserimento bulk di questi due model erano duplicati fra
`mobility.ingestion.materialization` e `mobility.services.reload`.
"""

from __future__ import annotations

from ..models import GpsPoint, StateTransition, Trip


def gps_point_count(trip: Trip) -> int:
    return GpsPoint.objects.filter(trip=trip).count()


def state_transition_count(trip: Trip) -> int:
    return StateTransition.objects.filter(trip=trip).count()


def gps_points_ordered(trip: Trip):
    return GpsPoint.objects.filter(trip=trip).order_by("timestamp", "id")


def bulk_create_gps_points(rows: list[GpsPoint]) -> None:
    GpsPoint.objects.bulk_create(rows, ignore_conflicts=True)


def bulk_create_state_transitions(rows: list[StateTransition]) -> None:
    StateTransition.objects.bulk_create(rows, ignore_conflicts=True)
