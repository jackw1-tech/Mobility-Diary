import hashlib
import secrets
from datetime import timedelta

from django.conf import settings
from django.db import models
from django.utils import timezone


class AccessToken(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name="access_tokens",
        on_delete=models.CASCADE,
    )
    token_hash = models.CharField(max_length=64, unique=True)
    device_name = models.CharField(max_length=128, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    revoked_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [
            models.Index(fields=["user", "expires_at"]),
            models.Index(fields=["token_hash"]),
        ]

    """
    Funzione che prende un token raw e lo converte in una stringa hashata con SHA-256
    """
    @staticmethod
    def hash_raw_token(raw_token: str) -> str:
        return hashlib.sha256(raw_token.encode("utf-8")).hexdigest()


    """
    Funzione della classe che server per creare un nuovo token di accesso,
    una volta creato, nel db non salviamo lui, ma salviamo una stringa ottenuto da SHA-256
    """
    @classmethod
    def issue_for_user(cls, user, *, device_name: str = ""):
        raw_token = secrets.token_urlsafe(48)
        ttl_days = getattr(settings, "MOBILE_ACCESS_TOKEN_TTL_DAYS", 30)

        access_token = cls.objects.create(
            user=user,
            token_hash=cls.hash_raw_token(raw_token),
            device_name=device_name[:128],
            expires_at=timezone.now() + timedelta(days=ttl_days),
        )
        return raw_token, access_token

    def revoke(self) -> None:
        self.revoked_at = timezone.now()
        self.save(update_fields=["revoked_at"])


class UserPrivacySettings(models.Model):
    class Level(models.TextChoices):
        PRECISE = "precise", "Precise"
        APPROXIMATE = "approximate", "Approximate"
        AGGREGATED = "aggregated", "Aggregated"

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        related_name="privacy_settings",
        on_delete=models.CASCADE,
    )
    level = models.CharField(
        max_length=16,
        choices=Level.choices,
        default=Level.PRECISE,
    )
    is_first_login = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)


class WebRefreshToken(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name="web_refresh_tokens",
        on_delete=models.CASCADE,
    )
    jti = models.CharField(max_length=64, unique=True)
    expires_at = models.DateTimeField()
    revoked_at = models.DateTimeField(null=True, blank=True)
    rotated_to_jti = models.CharField(max_length=64, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    last_used_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [
            models.Index(fields=["user", "expires_at"]),
            models.Index(fields=["jti"]),
        ]

    @property
    def is_valid(self) -> bool:
        return (
            self.revoked_at is None
            and self.expires_at > timezone.now()
            and self.user.is_active
            and (self.user.is_staff or self.user.is_superuser)
        )

    def revoke(self, *, rotated_to_jti: str = "") -> None:
        update_fields = ["last_used_at", "revoked_at"]
        self.last_used_at = timezone.now()
        self.revoked_at = timezone.now()
        if rotated_to_jti:
            self.rotated_to_jti = rotated_to_jti
            update_fields.append("rotated_to_jti")
        self.save(update_fields=update_fields)
