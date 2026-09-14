"""Create the local demo accounts when they do not exist."""

import os

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError

from accounts.models import UserPrivacySettings


DEFAULT_ADMIN_EMAIL = "admin@mobility.local"
DEFAULT_ADMIN_PASSWORD = "MobilityAdmin123!"
DEFAULT_USER_EMAIL = "user@mobility.local"
DEFAULT_USER_PASSWORD = "MobilityUser123!"


class Command(BaseCommand):
    help = "Create the idempotent accounts used by the local demo."

    def handle(self, *args, **options):
        admin_email = os.getenv(
            "DJANGO_DEMO_SUPERUSER_EMAIL",
            DEFAULT_ADMIN_EMAIL,
        ).strip()
        admin_password = os.getenv(
            "DJANGO_DEMO_SUPERUSER_PASSWORD",
            DEFAULT_ADMIN_PASSWORD,
        )
        user_email = os.getenv("DJANGO_DEMO_USER_EMAIL", DEFAULT_USER_EMAIL).strip()
        user_password = os.getenv(
            "DJANGO_DEMO_USER_PASSWORD",
            DEFAULT_USER_PASSWORD,
        )

        if not all((admin_email, admin_password, user_email, user_password)):
            raise CommandError("Demo account emails and passwords cannot be empty")
        if admin_email.casefold() == user_email.casefold():
            raise CommandError("Demo administrator and user must have different emails")

        self._ensure_administrator(admin_email, admin_password)
        self._ensure_mobile_user(user_email, user_password)

    def _ensure_administrator(self, email: str, password: str) -> None:
        user_model = get_user_model()
        user = user_model._default_manager.filter(email__iexact=email).first()
        if user is None:
            user_model._default_manager.create_superuser(
                username=email,
                email=email,
                password=password,
                first_name="Demo",
                last_name="Administrator",
            )
            self.stdout.write(self.style.SUCCESS(f"Created demo administrator: {email}"))
            return

        changed_fields = []
        for field in ("is_active", "is_staff", "is_superuser"):
            if not getattr(user, field):
                setattr(user, field, True)
                changed_fields.append(field)
        if changed_fields:
            user.save(update_fields=changed_fields)
        self.stdout.write(self.style.SUCCESS(f"Demo administrator already exists: {email}"))

    def _ensure_mobile_user(self, email: str, password: str) -> None:
        user_model = get_user_model()
        user = user_model._default_manager.filter(email__iexact=email).first()
        if user is None:
            user = user_model._default_manager.create_user(
                username=email,
                email=email,
                password=password,
                first_name="Demo",
                last_name="User",
            )
            message = f"Created demo mobile user: {email}"
        else:
            if not user.is_active:
                user.is_active = True
                user.save(update_fields=["is_active"])
            message = f"Demo mobile user already exists: {email}"

        UserPrivacySettings.objects.get_or_create(
            user=user,
            defaults={"level": UserPrivacySettings.Level.APPROXIMATE},
        )
        self.stdout.write(self.style.SUCCESS(message))
