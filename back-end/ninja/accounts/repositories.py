"""Repository del context accounts per gli aggregati User e UserPrivacySettings.

Unico punto del context in cui compaiono `User.objects` / `_default_manager`
e `UserPrivacySettings.objects`. I sottomoduli (auth_mobile, auth_web,
privacy) e altri context (mobility) che hanno bisogno di questi dati passano
da qui invece di interrogare direttamente i model Django.
"""

from __future__ import annotations

from django.contrib.auth import get_user_model
from django.db.models import Count, FloatField, Max, Q, QuerySet, Sum, Value
from django.db.models.functions import Coalesce


from mobility.models import Trip

from .models import UserPrivacySettings


def user_model():
    return get_user_model()


def user_by_email(email: str):
    """Utente con questa email (case-insensitive), o None."""
    return user_model()._default_manager.filter(email__iexact=email).first()


def email_is_taken(email: str) -> bool:
    return user_model()._default_manager.filter(email__iexact=email).exists()


def user_by_id(user_id: int):
    return user_model()._default_manager.filter(id=user_id).first()


def create_user(
    *,
    email: str,
    password: str,
    first_name: str,
    last_name: str,
):
    return user_model()._default_manager.create_user(
        username=email,
        email=email,
        password=password,
        first_name=first_name,
        last_name=last_name,
    )


def get_or_create_privacy_settings(user_id: int) -> UserPrivacySettings:
    settings, _ = UserPrivacySettings.objects.get_or_create(user_id=user_id)
    return settings


def create_privacy_settings(user) -> UserPrivacySettings:
    return UserPrivacySettings.objects.create(user=user)


def update_or_create_privacy_settings(
    user_id: int,
    *,
    level: str,
    is_first_login: bool,
) -> UserPrivacySettings:
    settings, _ = UserPrivacySettings.objects.update_or_create(
        user_id=user_id,
        defaults={"level": level, "is_first_login": is_first_login},
    )
    return settings


def web_user_overviews_queryset() -> QuerySet:
    """Utenti non staff, annotati con le statistiche Viaggio per la dashboard web."""
    return (
        user_model()
        ._default_manager.filter(is_staff=False, is_superuser=False)
        .annotate(
            trip_count=Count("trips", distinct=True),
            processed_trip_count=Count(
                "trips",
                filter=Q(trips__status=Trip.Status.PROCESSED),
                distinct=True,
            ),
            latest_trip_started_at=Max("trips__started_at"),
            total_distance_meters=Coalesce(
                Sum("trips__distance_meters"),
                Value(0.0),
                output_field=FloatField(),
            ),
        )
    )


def web_user_overview_values(queryset: QuerySet) -> QuerySet:
    return queryset.values(
        "id",
        "email",
        "first_name",
        "last_name",
        "is_active",
        "trip_count",
        "processed_trip_count",
        "latest_trip_started_at",
        "total_distance_meters",
    )
