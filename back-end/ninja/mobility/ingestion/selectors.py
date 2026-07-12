from __future__ import annotations

from django.db.models import QuerySet

from ..models import TripIngestion


def owned_ingestions_for_owner(user_id: int) -> QuerySet[TripIngestion]:
    return TripIngestion.objects.select_related("trip").filter(user_id=user_id)

""" 
Prende una trip ingestions solo se appartiene all'utente autenticato
"""
def active_ingestions_for_owner(user_id: int) -> QuerySet[TripIngestion]:
    return owned_ingestions_for_owner(user_id).filter(
        recording_started_at__isnull=False,
        recording_closed_at__isnull=True,
        recording_abandoned_at__isnull=True,
    )


"""
Controlla se un utente ha già una registrazione attiva in corso
Se ancora in corso, ottiene il lock su quella riga
"""
def locked_active_ingestions_for_owner(user_id: int) -> QuerySet[TripIngestion]:
    return TripIngestion.objects.filter(
        user_id=user_id,
        recording_started_at__isnull=False,
        recording_closed_at__isnull=True,
        recording_abandoned_at__isnull=True,
    ).select_for_update()
