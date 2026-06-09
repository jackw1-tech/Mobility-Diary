import json
from dataclasses import dataclass
from datetime import datetime, timezone as datetime_timezone
from typing import Any

from django.conf import settings
from django.utils import timezone
from redis import Redis
from redis.exceptions import RedisError

from .models import AccessToken


@dataclass(frozen=True)
class CachedMobileUser:
    id: int
    email: str
    first_name: str
    last_name: str
    is_staff: bool
    is_superuser: bool

    @property
    def is_authenticated(self) -> bool:
        return True

    def get_username(self) -> str:
        return self.email

    def as_payload(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "email": self.email,
            "first_name": self.first_name,
            "last_name": self.last_name,
            "is_staff": self.is_staff,
            "is_superuser": self.is_superuser,
        }

    @classmethod
    def from_payload(cls, payload: dict[str, Any]) -> "CachedMobileUser":
        return cls(
            id=int(payload["id"]),
            email=str(payload.get("email", "")),
            first_name=str(payload.get("first_name", "")),
            last_name=str(payload.get("last_name", "")),
            is_staff=bool(payload.get("is_staff", False)),
            is_superuser=bool(payload.get("is_superuser", False)),
        )


@dataclass(frozen=True)
class MobileAuthContext:
    token_hash: str
    token_id: int
    expires_at: datetime
    user: CachedMobileUser
    source: str

    @property
    def user_id(self) -> int:
        return self.user.id


def user_payload(user) -> dict[str, Any]:
    return {
        "id": user.id,
        "email": user.email,
        "first_name": user.first_name,
        "last_name": user.last_name,
        "is_staff": user.is_staff,
        "is_superuser": user.is_superuser,
    }


def cache_key_for_hash(token_hash: str) -> str:
    return f"mobile_auth:{token_hash}"


def cache_key_for_raw_token(raw_token: str) -> str:
    return cache_key_for_hash(AccessToken.hash_raw_token(raw_token))


def get_redis_client() -> Redis:
    return Redis.from_url(settings.REDIS_URL, decode_responses=True)


def cache_access_token(raw_token: str, access_token: AccessToken) -> None:
    ttl = _ttl_seconds(access_token.expires_at)
    if ttl <= 0:
        return

    payload = {
        "token_hash": access_token.token_hash,
        "token_id": access_token.id,
        "expires_at": access_token.expires_at.isoformat(),
        "user": user_payload(access_token.user),
    }

    try:
        get_redis_client().setex(
            cache_key_for_hash(access_token.token_hash),
            ttl,
            json.dumps(payload),
        )
    except RedisError:
        return


def get_cached_auth_context(raw_token: str) -> MobileAuthContext | None:
    token_hash = AccessToken.hash_raw_token(raw_token)
    try:
        raw_payload = get_redis_client().get(cache_key_for_hash(token_hash))
    except RedisError:
        return None

    if not raw_payload:
        return None

    try:
        payload = json.loads(raw_payload)
        expires_at = datetime.fromisoformat(payload["expires_at"])
        if timezone.is_naive(expires_at):
            expires_at = timezone.make_aware(expires_at, datetime_timezone.utc)
        if expires_at <= timezone.now():
            delete_cached_auth_context(token_hash)
            return None

        return MobileAuthContext(
            token_hash=str(payload["token_hash"]),
            token_id=int(payload["token_id"]),
            expires_at=expires_at,
            user=CachedMobileUser.from_payload(payload["user"]),
            source="redis",
        )
    except (KeyError, TypeError, ValueError, json.JSONDecodeError):
        delete_cached_auth_context(token_hash)
        return None


def delete_cached_auth_context(token_hash: str) -> None:
    try:
        get_redis_client().delete(cache_key_for_hash(token_hash))
    except RedisError:
        return


def context_from_access_token(access_token: AccessToken) -> MobileAuthContext:
    return MobileAuthContext(
        token_hash=access_token.token_hash,
        token_id=access_token.id,
        expires_at=access_token.expires_at,
        user=CachedMobileUser.from_payload(user_payload(access_token.user)),
        source="database",
    )


def _ttl_seconds(expires_at: datetime) -> int:
    return max(0, int((expires_at - timezone.now()).total_seconds()))
