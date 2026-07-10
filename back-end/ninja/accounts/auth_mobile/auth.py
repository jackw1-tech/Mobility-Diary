from ninja.security import HttpBearer

from ..models import AccessToken
from .session_cache import (
    cache_access_token,
    context_from_access_token,
    get_cached_auth_context,
)

"""
Classe di autenticazione, serve per agganciare all'oggetto request lo user corrispondente
"""
class MobileBearerAuth(HttpBearer):
    def authenticate(self, request, token: str):
        cached_context = get_cached_auth_context(token)
        if cached_context is not None:
            request.user = cached_context.user
            return cached_context

        token_hash = AccessToken.hash_raw_token(token)
        access_token = (
            AccessToken.objects.select_related("user")
            .filter(token_hash=token_hash)
            .first()
        )

        if access_token is None or not access_token.is_valid:
            return None

        cache_access_token(token, access_token)
        context = context_from_access_token(access_token)
        request.user = context.user
        return context


mobile_bearer_auth = MobileBearerAuth()
