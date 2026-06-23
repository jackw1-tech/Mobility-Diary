import traceback

from ninja import Router
from ninja.errors import HttpError

from .auth import mobile_bearer_auth
from .models import UserPrivacySettings
from .schemas import PrivacySettingsIn, PrivacySettingsOut

router = Router(tags=["privacy"])


def _payload(settings: UserPrivacySettings) -> dict:
    return {
        "privacy_level": settings.level,
        "is_first_login": settings.is_first_login,
    }


@router.get("/settings", response=PrivacySettingsOut, auth=mobile_bearer_auth)
def get_privacy_settings(request):
    # TEMPORARY debug instrumentation: surface the real traceback in the
    # response body instead of a bare 500, to find the root cause of the
    # production crash. Remove once diagnosed.
    try:
        settings, _ = UserPrivacySettings.objects.get_or_create(
            user=request.auth.user,
        )
        return _payload(settings)
    except Exception:
        raise HttpError(500, traceback.format_exc())


@router.put("/settings", response=PrivacySettingsOut, auth=mobile_bearer_auth)
def update_privacy_settings(request, payload: PrivacySettingsIn):
    allowed = set(UserPrivacySettings.Level.values)
    if payload.privacy_level not in allowed:
        raise HttpError(400, "Livello privacy non valido")

    settings, _ = UserPrivacySettings.objects.update_or_create(
        user=request.auth.user,
        defaults={"level": payload.privacy_level, "is_first_login": False},
    )
    return _payload(settings)
