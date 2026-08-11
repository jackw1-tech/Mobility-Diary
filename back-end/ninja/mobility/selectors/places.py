from __future__ import annotations

from ..models import HabitualPlace, PlaceMiningStatus


def confirmed_places_for_user(
    user_id: int,
    *,
    only_fields: tuple[str, ...] | None = None,
) -> list[HabitualPlace]:
    """Luoghi Confermati dell'utente, usati come overlay read-time del diario.

    Query unica per questa esigenza: prima era ripetuta identica in
    mobility.api, mobility.diary_export, accounts.auth_web.users_api e (con
    un sottoinsieme di campi via `.only()`) tre volte in
    mobility.selectors.analytics. `only_fields` preserva quell'ottimizzazione
    per i chiamanti che non hanno bisogno dell'oggetto completo.
    """
    queryset = HabitualPlace.objects.filter(
        user_id=user_id,
        state=HabitualPlace.State.CONFIRMED,
    )
    if only_fields:
        queryset = queryset.only(*only_fields)
    return list(queryset)


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
