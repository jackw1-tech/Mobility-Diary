from __future__ import annotations

from django.db.models import QuerySet

from ..models import TripIngestion


def owned_ingestions_for_owner(user_id: int) -> QuerySet[TripIngestion]:
    return TripIngestion.objects.select_related("trip").filter(user_id=user_id)


def locked_owned_ingestions_for_owner(user_id: int) -> QuerySet[TripIngestion]:
    return TripIngestion.objects.filter(user_id=user_id).select_for_update()


def active_ingestions_for_owner(user_id: int) -> QuerySet[TripIngestion]:
    return owned_ingestions_for_owner(user_id).filter(
        recording_started_at__isnull=False,
        recording_closed_at__isnull=True,
        recording_abandoned_at__isnull=True,
    )


def locked_active_ingestions_for_owner(user_id: int) -> QuerySet[TripIngestion]:
    return TripIngestion.objects.filter(
        user_id=user_id,
        recording_started_at__isnull=False,
        recording_closed_at__isnull=True,
        recording_abandoned_at__isnull=True,
    ).select_for_update()


def first_active_ingestion_for_owner(user_id: int) -> TripIngestion | None:
    return active_ingestions_for_owner(user_id).first()
