from datetime import datetime

from django.contrib.auth import authenticate, get_user_model
from ninja import Router, Schema

from ..common import user_payload
from ..schemas import MessageOut, UserOut
from .auth import (
    WebAuthError,
    is_web_staff_user,
    issue_web_tokens,
    revoke_web_refresh_token,
    rotate_web_refresh_token,
    web_dashboard_auth,
)

router = Router(tags=["web-auth"])


class WebLoginIn(Schema):
    email: str
    password: str


class WebRefreshTokenIn(Schema):
    refresh_token: str


class WebAuthOut(Schema):
    user: UserOut
    access_token: str
    refresh_token: str
    token_type: str
    access_expires_at: datetime
    refresh_expires_at: datetime


def _username_for_login(identifier: str) -> str:
    normalized = identifier.strip()
    UserModel = get_user_model()
    user = UserModel._default_manager.filter(email__iexact=normalized).first()
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
        return 401, {"detail": "Credenziali non valide"}
    if not is_web_staff_user(user):
        return 403, {"detail": "Accesso staff richiesto"}
    return issue_web_tokens(user)


@router.post(
    "/refresh",
    response={200: WebAuthOut, 401: MessageOut},
    auth=None,
)
def web_refresh(request, payload: WebRefreshTokenIn):
    try:
        return rotate_web_refresh_token(payload.refresh_token)
    except WebAuthError:
        return 401, {"detail": "Refresh token web non valido"}


@router.post(
    "/logout",
    response={200: MessageOut, 401: MessageOut},
    auth=None,
)
def web_logout(request, payload: WebRefreshTokenIn):
    try:
        revoke_web_refresh_token(payload.refresh_token)
    except WebAuthError:
        return 401, {"detail": "Refresh token web non valido"}
    return {"detail": "Logout effettuato"}


@router.get("/me", response=UserOut, auth=web_dashboard_auth)
def web_me(request):
    return user_payload(request.auth)
