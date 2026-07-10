import uuid
from datetime import timedelta
from typing import Any

import jwt
from django.conf import settings
from django.contrib.auth import get_user_model
from django.utils import timezone
from ninja.security import HttpBearer

from ..common import user_payload
from ..models import WebRefreshToken

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


def issue_web_tokens(user) -> dict[str, Any]:
    now = timezone.now()
    access_expires_at = now + timedelta(
        minutes=settings.WEB_ACCESS_TOKEN_TTL_MINUTES,
    )
    refresh_expires_at = now + timedelta(days=settings.WEB_REFRESH_TOKEN_TTL_DAYS)
    refresh_jti = str(uuid.uuid4())

    WebRefreshToken.objects.create(
        user=user,
        jti=refresh_jti,
        expires_at=refresh_expires_at,
    )

    return {
        "user": user_payload(user),
        "access_token": _encode_token(
            user,
            token_type=ACCESS_TOKEN_TYPE,
            expires_at=access_expires_at,
            jti=str(uuid.uuid4()),
        ),
        "refresh_token": _encode_token(
            user,
            token_type=REFRESH_TOKEN_TYPE,
            expires_at=refresh_expires_at,
            jti=refresh_jti,
        ),
        "token_type": "Bearer",
        "access_expires_at": access_expires_at,
        "refresh_expires_at": refresh_expires_at,
    }


def rotate_web_refresh_token(raw_refresh_token: str) -> dict[str, Any]:
    claims = _decode_token(raw_refresh_token, expected_type=REFRESH_TOKEN_TYPE)
    stored = _get_valid_refresh_token(claims["jti"])
    new_tokens = issue_web_tokens(stored.user)
    new_claims = _decode_token(
        new_tokens["refresh_token"],
        expected_type=REFRESH_TOKEN_TYPE,
    )
    stored.revoke(rotated_to_jti=new_claims["jti"])
    return new_tokens


def revoke_web_refresh_token(raw_refresh_token: str) -> None:
    claims = _decode_token(raw_refresh_token, expected_type=REFRESH_TOKEN_TYPE)
    _get_valid_refresh_token(claims["jti"]).revoke()


def _encode_token(user, *, token_type: str, expires_at, jti: str) -> str:
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


def _decode_token(raw_token: str, *, expected_type: str) -> dict[str, Any]:
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


def _get_valid_refresh_token(jti: str) -> WebRefreshToken:
    stored = (
        WebRefreshToken.objects.select_related("user")
        .filter(jti=jti)
        .first()
    )
    if stored is None or not stored.is_valid:
        raise WebAuthError("Refresh token web non valido")
    return stored


class WebDashboardAuth(HttpBearer):
    def authenticate(self, request, token: str):
        try:
            claims = _decode_token(token, expected_type=ACCESS_TOKEN_TYPE)
        except WebAuthError:
            return None

        user = get_user_model()._default_manager.filter(id=claims["sub"]).first()
        if not is_web_staff_user(user):
            return None

        request.user = user
        return user


web_dashboard_auth = WebDashboardAuth()
