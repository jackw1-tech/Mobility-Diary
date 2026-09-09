from __future__ import annotations

from ..models import HabitualPlace, PlaceMiningStatus


"""Get dei luoghi congermati dall'utente"""
def confirmed_places_for_user(
    user_id: int,
    *,
    only_fields: tuple[str, ...] | None = None,
) -> list[HabitualPlace]:
    queryset = HabitualPlace.objects.filter(
        user_id=user_id,
        state=HabitualPlace.State.CONFIRMED,
    )
    if only_fields:
        queryset = queryset.only(*only_fields)
    return list(queryset)


#Restituisce la lista degli habitual place -> i miei luoghi nel front nd
def place_review_queryset_for_user(user_id: int):
    return (
        HabitualPlace.objects.filter(user_id=user_id)
        .prefetch_related("visits")
        .order_by("state", "-visit_count")
    )


def owned_place_for_user(user_id: int, place_id: int) -> HabitualPlace | None:
    return HabitualPlace.objects.filter(id=place_id, user_id=user_id).first()


def place_mining_status_row_for_user(user_id: int) -> dict:
    row = (
        PlaceMiningStatus.objects.filter(user_id=user_id)
        .values(
            "status",
            "requested_at",
            "started_at",
            "finished_at",
            "error_message",
            "rerun_requested",
        )
        .first()
    )
    return row or {
        "status": PlaceMiningStatus.Status.IDLE,
        "error_message": "",
        "rerun_requested": False,
    }


def place_mining_status_value_for_user(user_id: int) -> str:
    return (
        PlaceMiningStatus.objects.filter(user_id=user_id)
        .values_list("status", flat=True)
        .first()
        or PlaceMiningStatus.Status.IDLE
    )
