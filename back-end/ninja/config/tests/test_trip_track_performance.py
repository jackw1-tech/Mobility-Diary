from datetime import datetime, timedelta, timezone
from time import perf_counter

import pytest
from django.contrib.gis.geos import LineString, Point

from mobility.models import GpsPoint, Trip


pytestmark = pytest.mark.django_db


def test_track_endpoint_stays_fast_for_a_long_trip(api_client, mobile_session):
    point_count = 6831
    coordinates = [
        (9.19 + index * 0.000001, 45.46 + index * 0.000001)
        for index in range(point_count)
    ]
    trip = Trip.objects.create(
        user_id=mobile_session["user"]["id"],
        device_id="track-performance-test",
        status=Trip.Status.PROCESSED,
        path=LineString(coordinates, srid=4326),
        distance_meters=9500.0,
    )
    started_at = datetime(2026, 9, 3, tzinfo=timezone.utc)
    GpsPoint.objects.bulk_create(
        [
            GpsPoint(
                trip=trip,
                timestamp=started_at + timedelta(milliseconds=index * 100),
                point=Point(longitude, latitude, srid=4326),
            )
            for index, (longitude, latitude) in enumerate(coordinates)
        ],
        batch_size=1000,
    )

    started = perf_counter()
    response = api_client.get(
        f"/api/mobility/trips/{trip.id}/track",
        **mobile_session["headers"],
    )
    elapsed_seconds = perf_counter() - started

    assert response.status_code == 200
    assert response.json()["point_count"] == point_count
    assert len(response.json()["geojson"]["coordinates"]) == point_count
    assert elapsed_seconds < 2
