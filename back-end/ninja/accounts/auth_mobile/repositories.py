"""Repository dell'AccessToken (autenticazione mobile).

Unico punto del sottomodulo auth_mobile in cui compare `AccessToken.objects`.
"""

from __future__ import annotations

from datetime import datetime

from django.utils import timezone

from ..models import AccessToken

""" 
Generato il token casuale e hashato, lo storiamo nel db
"""
def create_access_token(
    user,
    *,
    token_hash: str,
    expires_at: datetime,
) -> AccessToken:
    return AccessToken.objects.create(
        user=user,
        token_hash=token_hash,
        expires_at=expires_at,
    )

""" 
Cerca il token nel db , nella tabella AccessToken
"""
def access_token_by_hash(token_hash: str) -> AccessToken | None:
    return (
        AccessToken.objects.select_related("user")
        .filter(token_hash=token_hash)
        .first()
    )


def revoke_access_token_by_hash(token_hash: str) -> None:
    AccessToken.objects.filter(token_hash=token_hash).update(
        revoked_at=timezone.now()
    )
