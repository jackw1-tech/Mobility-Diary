"""Business logic dell'autenticazione mobile (registrazione, login, logout).

Orchestra le regole di dominio e delega la persistenza ai repository
(`accounts.repositories` per User/UserPrivacySettings,
`accounts.auth_mobile.repositories` per AccessToken). Nessuna query ORM
diretta in questo modulo.
"""

from __future__ import annotations

import secrets
from datetime import timedelta

from django.conf import settings
from django.contrib.auth import authenticate
from django.core.exceptions import ValidationError as DjangoValidationError
from django.core.validators import validate_email
from django.contrib.auth.password_validation import validate_password
from django.db import IntegrityError, transaction
from django.utils import timezone

from shared.exceptions import ServiceError

from .. import repositories
from ..common import user_payload
from ..models import AccessToken
from . import repositories as auth_mobile_repositories
from .session_cache import cache_access_token, delete_cached_auth_context


class AuthMobileServiceError(ServiceError):
    status_code = 400


class InvalidEmail(AuthMobileServiceError):
    status_code = 400


class InvalidPassword(AuthMobileServiceError):
    status_code = 400


class EmailAlreadyRegistered(AuthMobileServiceError):
    status_code = 409


class InvalidCredentials(AuthMobileServiceError):
    status_code = 401


class UserDisabled(AuthMobileServiceError):
    status_code = 403


def _clean_email(email: str) -> str:
    normalized = email.strip().lower()
    try:
        validate_email(normalized)
    except DjangoValidationError as exc:
        raise InvalidEmail("Email non valida") from exc
    return normalized

"""Genera il token , lo stora hashato e lo mette in cache."""
def issue_access_token_for_user(user) -> tuple[str, AccessToken]:
    raw_token = secrets.token_urlsafe(48) # 64 caratteri
    ttl_days = settings.MOBILE_ACCESS_TOKEN_TTL_DAYS
    access_token = auth_mobile_repositories.create_access_token(
        user,
        token_hash=AccessToken.hash_raw_token(raw_token),
        expires_at=timezone.now() + timedelta(days=ttl_days),
    )
    cache_access_token(access_token)
    return raw_token, access_token


def _login_response(user, access_token: AccessToken, raw_token: str) -> dict:
    return {
        "user": user_payload(user),
        "access_token": raw_token,
        "token_type": "Bearer",
        "expires_at": access_token.expires_at,
    }


def register_user(
    *,
    email: str,
    password: str,
    first_name: str,
    last_name: str,
) -> dict:
    """Registra un nuovo utente, gli assegna le impostazioni privacy di default e lo autentica."""
    clean_email = _clean_email(email)

    if repositories.email_is_taken(clean_email):
        raise EmailAlreadyRegistered("Email gia registrata")

    try:
        validate_password(password)
    except DjangoValidationError as exc:
        raise InvalidPassword(" ".join(exc.messages)) from exc

    try:
        with transaction.atomic():
            user = repositories.create_user(
                email=clean_email,
                password=password,
                first_name=first_name.strip(),
                last_name=last_name.strip(),
            )
            repositories.create_privacy_settings(user)
    except IntegrityError as exc:
        raise EmailAlreadyRegistered("Email gia registrata") from exc

    raw_token, access_token = issue_access_token_for_user(user)
    return _login_response(user, access_token, raw_token)


def login_user(request, *, email: str, password: str) -> dict:
    normalized_email = email.strip().lower()
    account = repositories.user_by_email(normalized_email)
    if account is None:
        raise InvalidCredentials("Credenziali non valide")
    if not account.is_active:
        raise UserDisabled("Utente disabilitato")

    user = authenticate(
        request,
        username=account.get_username(),
        password=password,
    )
    if user is None:
        raise InvalidCredentials("Credenziali non valide")

    raw_token, access_token = issue_access_token_for_user(user)
    return _login_response(user, access_token, raw_token)


def logout_user(token_hash: str) -> None:
    delete_cached_auth_context(token_hash)
    auth_mobile_repositories.revoke_access_token_by_hash(token_hash)
