from ninja import Router
from ninja.errors import HttpError

from ..auth_mobile.auth import mobile_bearer_auth
from ..models import UserPrivacySettings
from .schemas import PrivacySettingsIn, PrivacySettingsOut

router = Router(tags=["privacy"])


def _payload(settings: UserPrivacySettings) -> dict:
    return {
        "privacy_level": settings.level,
        "is_first_login": settings.is_first_login,
    }



"""
Rotta richiamata per sapere se è il primo login dell'utente -> fai decidere il profilo di privacy
e nelle impostazioni
"""
@router.get("/settings", response=PrivacySettingsOut, auth=mobile_bearer_auth)
def get_privacy_settings(request):
    settings, _ = UserPrivacySettings.objects.get_or_create(
        user_id=request.auth.user_id,
    )
    return _payload(settings)

"""
Rotta per cambiare il livello di privacy dell'utente
"""
@router.put("/settings", response=PrivacySettingsOut, auth=mobile_bearer_auth)
def update_privacy_settings(request, payload: PrivacySettingsIn):
    allowed = set(UserPrivacySettings.Level.values)
    if payload.privacy_level not in allowed:
        raise HttpError(400, "Livello privacy non valido")

    settings, _ = UserPrivacySettings.objects.update_or_create(
        user_id=request.auth.user_id,
        defaults={"level": payload.privacy_level, "is_first_login": False},
    )
    return _payload(settings)
