from datetime import timedelta

import pytest
from django.contrib.auth import get_user_model
from django.utils import timezone

from mobility.ingestion.selectors import (
    active_ingestions_for_owner,
    first_active_ingestion_for_owner,
    owned_ingestions_for_owner,
)
from mobility.models import TripIngestion


@pytest.fixture
def users(db):
    model = get_user_model()
    return (
        model.objects.create_user(
            username="owner@example.com",
            email="owner@example.com",
            password="password-123",
        ),
        model.objects.create_user(
            username="other@example.com",
            email="other@example.com",
            password="password-123",
        ),
    )


@pytest.mark.django_db
def test_active_ingestions_for_owner_returns_only_open_recordings(users):
    owner, other = users
    started_at = timezone.now() - timedelta(minutes=10)
    active = TripIngestion.objects.create(
        user=owner,
        client_session_id="active",
        recording_started_at=started_at,
    )
    TripIngestion.objects.create(
        user=owner,
        client_session_id="closed",
        recording_started_at=started_at,
        recording_closed_at=timezone.now(),
    )
    TripIngestion.objects.create(
        user=owner,
        client_session_id="abandoned",
        recording_started_at=started_at,
        recording_abandoned_at=timezone.now(),
    )
    TripIngestion.objects.create(
        user=other,
        client_session_id="other-active",
        recording_started_at=started_at,
    )

    assert list(active_ingestions_for_owner(owner.id)) == [active]
    assert first_active_ingestion_for_owner(owner.id) == active


@pytest.mark.django_db
def test_first_active_ingestion_for_owner_returns_none_without_active_recording(users):
    owner, _other = users
    TripIngestion.objects.create(
        user=owner,
        client_session_id="plain-ingestion",
    )

    assert first_active_ingestion_for_owner(owner.id) is None


@pytest.mark.django_db
def test_owned_ingestions_for_owner_filters_by_user(users):
    owner, other = users
    owner_ingestion = TripIngestion.objects.create(
        user=owner,
        client_session_id="owner-ingestion",
    )
    TripIngestion.objects.create(
        user=other,
        client_session_id="other-ingestion",
    )

    assert list(owned_ingestions_for_owner(owner.id)) == [owner_ingestion]
