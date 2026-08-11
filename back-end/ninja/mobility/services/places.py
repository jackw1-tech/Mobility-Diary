from __future__ import annotations

from dataclasses import dataclass

from shared.exceptions import ServiceError

from ..models import HabitualPlace, PlaceMiningStatus
from ..selectors.places import (
    owned_place_for_user,
    place_mining_status_value_for_user,
)


class PlaceServiceError(ServiceError):
    status_code = 409


class PlaceNotFound(PlaceServiceError):
    status_code = 404


class PlaceValidationError(PlaceServiceError):
    status_code = 422


@dataclass(frozen=True)
class PlaceMutationBlocked:
    detail: str
    code: str
    status: str


class PlaceMutationBlockedError(PlaceServiceError):
    status_code = 409

    def __init__(self, block: PlaceMutationBlocked):
        super().__init__(block.detail)
        self.block = block


VALID_PLACE_CATEGORIES = {choice.value for choice in HabitualPlace.Category}


def place_mutation_block_for_user(user_id: int) -> PlaceMutationBlocked | None:
    status = place_mining_status_value_for_user(user_id)
    if status == PlaceMiningStatus.Status.SUCCEEDED:
        return None
    return PlaceMutationBlocked(
        detail="analisi dei luoghi abituali non completata",
        code="place_mining_not_ready",
        status=status,
    )


def confirm_place_for_user(user_id: int, place_id: int) -> HabitualPlace:
    place = _editable_place(user_id, place_id)
    place.state = HabitualPlace.State.CONFIRMED
    place.manually_reviewed = True
    place.save(update_fields=["state", "manually_reviewed", "updated_at"])
    return place


def reject_place_for_user(user_id: int, place_id: int) -> HabitualPlace:
    place = _editable_place(user_id, place_id)
    place.state = HabitualPlace.State.REJECTED
    place.manually_reviewed = True
    place.save(update_fields=["state", "manually_reviewed", "updated_at"])
    return place


def reactivate_place_for_user(user_id: int, place_id: int) -> HabitualPlace:
    place = _editable_place(user_id, place_id)
    place.state = HabitualPlace.State.CANDIDATE
    place.manually_reviewed = False
    place.save(update_fields=["state", "manually_reviewed", "updated_at"])
    return place


def label_place_for_user(
    user_id: int,
    place_id: int,
    *,
    category: str,
    custom_name: str,
) -> HabitualPlace:
    if category and category not in VALID_PLACE_CATEGORIES:
        raise PlaceValidationError("categoria non valida")
    place = _editable_place(user_id, place_id)
    place.category = category
    place.custom_name = custom_name
    place.manually_reviewed = True
    place.save(update_fields=["category", "custom_name", "manually_reviewed", "updated_at"])
    return place


def _editable_place(user_id: int, place_id: int) -> HabitualPlace:
    place = owned_place_for_user(user_id, place_id)
    if place is None:
        raise PlaceNotFound("luogo non trovato")

    blocked = place_mutation_block_for_user(user_id)
    if blocked is not None:
        raise PlaceMutationBlockedError(blocked)

    return place
