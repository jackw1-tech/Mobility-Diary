"""Repository del WebRefreshToken
"""

from __future__ import annotations

from datetime import datetime

from ..models import WebRefreshToken


def create_refresh_token(user, *, jti: str, expires_at: datetime) -> WebRefreshToken:
    return WebRefreshToken.objects.create(
        user=user,
        jti=jti,
        expires_at=expires_at,
    )


def refresh_token_by_jti(jti: str) -> WebRefreshToken | None:
    return (
        WebRefreshToken.objects.select_related("user")
        .filter(jti=jti)
        .first()
    )
