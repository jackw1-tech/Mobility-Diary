"""Services dell'autenticazione web
"""

from __future__ import annotations

import uuid
from datetime import timedelta
from typing import Any

from django.conf import settings
from django.utils import timezone

from ..common import user_payload
from . import repositories
from .auth import (
    ACCESS_TOKEN_TYPE,
    REFRESH_TOKEN_TYPE,
    WebAuthError,
    decode_token,
    encode_token,
)


def issue_web_tokens(user) -> dict[str, Any]:
    now = timezone.now()
    access_expires_at = now + timedelta(
        minutes=settings.WEB_ACCESS_TOKEN_TTL_MINUTES,
    )
    refresh_expires_at = now + timedelta(days=settings.WEB_REFRESH_TOKEN_TTL_DAYS)
    refresh_jti = str(uuid.uuid4())

    repositories.create_refresh_token(
        user,
        jti=refresh_jti,
        expires_at=refresh_expires_at,
    )

    return {
        "user": user_payload(user),
        "access_token": encode_token(
            user,
            token_type=ACCESS_TOKEN_TYPE,
            expires_at=access_expires_at,
            jti=str(uuid.uuid4()),
        ),
        "refresh_token": encode_token(
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
    claims = decode_token(raw_refresh_token, expected_type=REFRESH_TOKEN_TYPE)
    stored = _valid_refresh_token_or_error(claims["jti"])
    new_tokens = issue_web_tokens(stored.user)
    new_claims = decode_token(
        new_tokens["refresh_token"],
        expected_type=REFRESH_TOKEN_TYPE,
    )
    stored.revoke(rotated_to_jti=new_claims["jti"])
    return new_tokens


def revoke_web_refresh_token(raw_refresh_token: str) -> None:
    claims = decode_token(raw_refresh_token, expected_type=REFRESH_TOKEN_TYPE)
    _valid_refresh_token_or_error(claims["jti"]).revoke()


def _valid_refresh_token_or_error(jti: str):
    stored = repositories.refresh_token_by_jti(jti)
    if stored is None or not stored.is_valid:
        raise WebAuthError("Refresh token web non valido")
    return stored
