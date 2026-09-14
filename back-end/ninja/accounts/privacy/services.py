from __future__ import annotations

from shared.exceptions import ServiceError

from .. import repositories
from ..models import UserPrivacySettings


class PrivacyServiceError(ServiceError):
    status_code = 400


class InvalidPrivacyLevel(PrivacyServiceError):
    status_code = 400


def _payload(settings: UserPrivacySettings) -> dict:
    return {
        "privacy_level": settings.level,
        "is_first_login": settings.is_first_login,
    }

"""Preferenza privacy corrente; la crea con i default se è il primo accesso."""
def get_privacy_settings(user_id: int) -> dict:
    settings = repositories.get_or_create_privacy_settings(user_id)
    return _payload(settings)


def update_privacy_settings(user_id: int, *, privacy_level: str) -> dict:
    if privacy_level not in set(UserPrivacySettings.Level.values):
        raise InvalidPrivacyLevel("Livello privacy non valido")

    settings = repositories.update_or_create_privacy_settings(
        user_id,
        level=privacy_level,
        is_first_login=False,
    )
    return _payload(settings)
