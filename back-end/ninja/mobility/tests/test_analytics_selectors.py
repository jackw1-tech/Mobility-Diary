from datetime import datetime, timedelta, timezone as dt_timezone

import pytest
from django.contrib.auth import get_user_model
from django.contrib.gis.geos import LineString, Point
from django.utils import timezone

from mobility.models import ActivityLabel, HabitualPlace, MobilitySegment, Trip
from mobility.selectors.analytics import personal_analytics_for_user


@pytest.fixture
def mobile_user(db):
    return get_user_model().objects.create_user(
        username="analytics@example.com",
        email="analytics@example.com",
        password="password-123",
    )


def _category(bucket, name: str):
    return next(item for item in bucket.categories if item.category == name)


@pytest.mark.django_db
def test_personal_analytics_selector_builds_representative_read_model(mobile_user):
    now = timezone.now().astimezone(dt_timezone.utc)
    base = now.replace(hour=8, minute=0, second=0, microsecond=0) - timedelta(days=1)
    trip = Trip.objects.create(
        user=mobile_user,
        client_session_id="analytics-trip",
        status=Trip.Status.PROCESSED,
        started_at=base,
        ended_at=base + timedelta(minutes=45),
        path=LineString((9.10, 45.46), (9.12, 45.47), srid=4326),
    )
    HabitualPlace.objects.create(
        user=mobile_user,
        center=Point(9.10, 45.46, srid=4326),
        radius_meters=500,
        state=HabitualPlace.State.CONFIRMED,
        category=HabitualPlace.Category.CASA,
        custom_name="Casa",
        visit_count=4,
    )
    HabitualPlace.objects.create(
        user=mobile_user,
        center=Point(9.12, 45.47, srid=4326),
        radius_meters=500,
        state=HabitualPlace.State.CONFIRMED,
        category=HabitualPlace.Category.UNIVERSITA,
        custom_name="Universita",
        visit_count=2,
    )
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.MOVE,
        start_timestamp=base,
        end_timestamp=base + timedelta(minutes=20),
        activity_label=ActivityLabel.BIKING,
        distance_meters=2000,
    )
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.MOVE,
        start_timestamp=base + timedelta(minutes=20),
        end_timestamp=base + timedelta(minutes=30),
        activity_label=ActivityLabel.WALKING,
        distance_meters=800,
    )

    analytics = personal_analytics_for_user(
        user_id=mobile_user.id,
        granularity="day",
        tz="UTC",
    )
    weekly = personal_analytics_for_user(
        user_id=mobile_user.id,
        granularity="week",
        tz="UTC",
    )

    assert analytics.has_data is True
    assert analytics.granularity == "day"
    assert len(analytics.buckets) == 1
    assert _category(analytics.buckets[0], "in_bici").seconds == 20 * 60
    assert _category(analytics.buckets[0], "in_bici").distance_meters == 2000
    assert _category(analytics.buckets[0], "a_piedi").seconds == 10 * 60
    assert weekly.granularity == "week"
    assert weekly.buckets
    assert analytics.prevalent_mode == "in_bici"
    assert [(point.lat, point.lon, point.weight) for point in analytics.heatmap] == [
        (45.46, 9.10, 4.0),
        (45.47, 9.12, 2.0),
    ]
    assert analytics.weekly_heatmaps
    assert trip.id in analytics.weekly_heatmaps[-1].trip_ids
    assert analytics.frequent_routes[0].origin_label == "Casa"
    assert analytics.frequent_routes[0].destination_label == "Universita"
    assert analytics.frequent_routes[0].trip_count == 1
