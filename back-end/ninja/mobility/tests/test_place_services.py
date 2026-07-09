import pytest
from django.contrib.auth import get_user_model
from django.contrib.gis.geos import Point

from mobility.models import HabitualPlace, PlaceMiningStatus
from mobility.services.places import (
    PlaceMutationBlockedError,
    PlaceNotFound,
    PlaceValidationError,
    confirm_place_for_user,
    label_place_for_user,
)


@pytest.fixture
def mobile_user(db):
    return get_user_model().objects.create_user(
        username="place-service@example.com",
        email="place-service@example.com",
        password="password-123",
    )


@pytest.fixture
def review_ready_place(mobile_user):
    PlaceMiningStatus.objects.create(
        user=mobile_user,
        status=PlaceMiningStatus.Status.SUCCEEDED,
    )
    return HabitualPlace.objects.create(
        user=mobile_user,
        center=Point(9.19, 45.46, srid=4326),
        radius_meters=80,
        visit_count=3,
        distinct_days=2,
    )


@pytest.mark.django_db
def test_confirm_place_marks_it_reviewed(review_ready_place, mobile_user):
    place = confirm_place_for_user(mobile_user.id, review_ready_place.id)

    assert place.state == HabitualPlace.State.CONFIRMED
    assert place.manually_reviewed is True


@pytest.mark.django_db
def test_label_place_validates_category(review_ready_place, mobile_user):
    with pytest.raises(PlaceValidationError, match="categoria non valida"):
        label_place_for_user(
            mobile_user.id,
            review_ready_place.id,
            category="nope",
            custom_name="Casa",
        )


@pytest.mark.django_db
def test_place_mutation_checks_ownership_before_mining_status(mobile_user):
    PlaceMiningStatus.objects.create(
        user=mobile_user,
        status=PlaceMiningStatus.Status.PENDING,
    )

    with pytest.raises(PlaceNotFound):
        confirm_place_for_user(mobile_user.id, 999999)


@pytest.mark.django_db
def test_place_mutation_blocks_when_mining_is_not_ready(mobile_user):
    PlaceMiningStatus.objects.create(
        user=mobile_user,
        status=PlaceMiningStatus.Status.PENDING,
    )
    place = HabitualPlace.objects.create(
        user=mobile_user,
        center=Point(9.19, 45.46, srid=4326),
    )

    with pytest.raises(PlaceMutationBlockedError) as exc_info:
        confirm_place_for_user(mobile_user.id, place.id)

    assert exc_info.value.block.status == PlaceMiningStatus.Status.PENDING
