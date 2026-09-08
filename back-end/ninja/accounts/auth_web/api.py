from django.contrib.auth import authenticate
from ninja import Router
from ninja.responses import Status

from .. import repositories as accounts_repositories
from ..common import user_payload
from ..schemas import MessageOut, UserOut
from . import services
from .auth import (
    WebAuthError,
    is_web_staff_user,
    web_dashboard_auth,
)
from .schemas import WebAuthOut, WebLoginIn, WebRefreshTokenIn

router = Router(tags=["web-auth"])


def _username_for_login(identifier: str) -> str:
    normalized = identifier.strip()
    user = accounts_repositories.user_by_email(normalized)
    if user is not None:
        return user.get_username()
    return normalized


@router.post(
    "/login",
    response={200: WebAuthOut, 401: MessageOut, 403: MessageOut},
    auth=None,
)
def web_login(request, payload: WebLoginIn):
    username = _username_for_login(payload.email)
    user = authenticate(request, username=username, password=payload.password)
    if user is None:
        return Status(401, {"detail": "Credenziali non valide"})
    if not is_web_staff_user(user):
        return Status(403, {"detail": "Accesso staff richiesto"})
    return services.issue_web_tokens(user)


@router.post(
    "/refresh",
    response={200: WebAuthOut, 401: MessageOut},
    auth=None,
)
def web_refresh(request, payload: WebRefreshTokenIn):
    try:
        return services.rotate_web_refresh_token(payload.refresh_token)
    except WebAuthError:
        return Status(401, {"detail": "Refresh token web non valido"})


@router.post(
    "/logout",
    response={200: MessageOut, 401: MessageOut},
    auth=None,
)
def web_logout(request, payload: WebRefreshTokenIn):
    try:
        services.revoke_web_refresh_token(payload.refresh_token)
    except WebAuthError:
        return Status(401, {"detail": "Refresh token web non valido"})
    return {"detail": "Logout effettuato"}


@router.get("/me", response=UserOut, auth=web_dashboard_auth)
def web_me(request):
    return user_payload(request.user)
