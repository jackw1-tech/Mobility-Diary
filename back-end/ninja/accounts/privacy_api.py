from ninja import Router
from ninja.errors import HttpError

from .auth import mobile_bearer_auth
from .models import UserPrivacySettings
from .schemas import PrivacySettingsIn, PrivacySettingsOut

router = Router(tags=["privacy"])


def _payload(settings: UserPrivacySettings) -> dict:
    return {"privacy_level": settings.level}


@router.get("/settings", response=PrivacySettingsOut, auth=mobile_bearer_auth)
def get_privacy_settings(request):
    settings, _ = UserPrivacySettings.objects.get_or_create(
        user=request.auth.user,
    )
    return _payload(settings)


@router.put("/settings", response=PrivacySettingsOut, auth=mobile_bearer_auth)
def update_privacy_settings(request, payload: PrivacySettingsIn):
    allowed = set(UserPrivacySettings.Level.values)
    if payload.privacy_level not in allowed:
        raise HttpError(400, "Livello privacy non valido")

    settings, _ = UserPrivacySettings.objects.update_or_create(
        user=request.auth.user,
        defaults={"level": payload.privacy_level},
    )
    return _payload(settings)
