from ninja.security import HttpBearer

from ..models import AccessToken
from . import repositories
from .session_cache import (
    cache_access_token,
    context_from_access_token,
    delete_cached_auth_context,
    get_cached_auth_context,
)

"""
Classe di autenticazione, serve per agganciare all'oggetto request lo user corrispondente
"""
class MobileBearerAuth(HttpBearer):
    def authenticate(self, request, token: str):
        cached_context = get_cached_auth_context(token)
        if cached_context is not None:
            access_token = repositories.access_token_by_hash(
                cached_context.token_hash
            )
            if access_token is None or not access_token.is_valid:
                delete_cached_auth_context(cached_context.token_hash)
                return None
            request.user = cached_context
            return cached_context

        token_hash = AccessToken.hash_raw_token(token)
        access_token = repositories.access_token_by_hash(token_hash)

        if access_token is None or not access_token.is_valid:
            return None

        cache_access_token(access_token)
        context = context_from_access_token(access_token)
        request.user = context
        return context


mobile_bearer_auth = MobileBearerAuth()
