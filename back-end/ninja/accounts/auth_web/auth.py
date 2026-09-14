from __future__ import annotations

from typing import Any

import jwt
from django.conf import settings
from django.utils import timezone
from ninja.security import HttpBearer

from .. import repositories as accounts_repositories

JWT_ALGORITHM = "HS256"
ACCESS_TOKEN_TYPE = "web_access"
REFRESH_TOKEN_TYPE = "web_refresh"


class WebAuthError(ValueError):
    pass


def is_web_staff_user(user) -> bool:
    return bool(
        user is not None
        and user.is_active
        and (user.is_staff or user.is_superuser)
    )


def encode_token(user, *, token_type: str, expires_at, jti: str) -> str:
    now = timezone.now()
    return jwt.encode(
        {
            "type": token_type,
            "sub": str(user.id),
            "jti": jti,
            "iat": int(now.timestamp()),
            "exp": int(expires_at.timestamp()),
        },
        settings.SECRET_KEY,
        algorithm=JWT_ALGORITHM,
    )


def decode_token(raw_token: str, *, expected_type: str) -> dict[str, Any]:
    try:
        claims = jwt.decode(
            raw_token,
            settings.SECRET_KEY,
            algorithms=[JWT_ALGORITHM],
        )
    except jwt.InvalidTokenError as exc:
        raise WebAuthError("Token web non valido") from exc

    if claims.get("type") != expected_type:
        raise WebAuthError("Tipo token web non valido")
    if not claims.get("sub") or not claims.get("jti"):
        raise WebAuthError("Token web incompleto")
    return claims


class WebDashboardAuth(HttpBearer):
    def authenticate(self, request, token: str):
        try:
            claims = decode_token(token, expected_type=ACCESS_TOKEN_TYPE)
        except WebAuthError:
            return None

        user = accounts_repositories.user_by_id(int(claims["sub"]))
        if not is_web_staff_user(user):
            return None

        request.user = user
        return user


web_dashboard_auth = WebDashboardAuth()
