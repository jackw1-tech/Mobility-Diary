from ninja import Router
from ninja.errors import HttpError

from ..auth_mobile.auth import mobile_bearer_auth
from . import services
from .schemas import PrivacySettingsIn, PrivacySettingsOut

router = Router(tags=["privacy"])


"""
Rotta richiamata per sapere se è il primo login dell'utente -> fai decidere il profilo di privacy
e nelle impostazioni
"""
@router.get("/settings", response=PrivacySettingsOut, auth=mobile_bearer_auth)
def get_privacy_settings(request):
    return services.get_privacy_settings(request.user.user_id)


"""
Rotta per cambiare il livello di privacy dell'utente
"""
@router.put("/settings", response=PrivacySettingsOut, auth=mobile_bearer_auth)
def update_privacy_settings(request, payload: PrivacySettingsIn):
    try:
        return services.update_privacy_settings(
            request.user.user_id,
            privacy_level=payload.privacy_level,
        )
    except services.PrivacyServiceError as exc:
        raise HttpError(exc.status_code, exc.message) from exc
