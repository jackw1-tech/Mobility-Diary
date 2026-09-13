from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

import pytest
from django.contrib.gis.geos import LineString, Point

from mobility.models import (
    CandidateVisit,
    HabitualPlace,
    MobilitySegment,
    PlaceMiningStatus,
    Trip,
)
from mobility.services.analytics import frequent_routes, weekly_heatmaps

from .test_upload_and_trips_api import complete_core, post_json, start_recording


pytestmark = pytest.mark.django_db


def create_candidate_place(user_id):
    place = HabitualPlace.objects.create(
        user_id=user_id,
        center=Point(9.1900, 45.4642, srid=4326),
        radius_meters=45,
        state=HabitualPlace.State.CANDIDATE,
        visit_count=3,
        distinct_days=2,
    )
    CandidateVisit.objects.create(
        user_id=user_id,
        place=place,
        center=Point(9.1901, 45.4643, srid=4326),
        started_at=datetime(2026, 8, 28, 8, 0, tzinfo=timezone.utc),
        ended_at=datetime(2026, 8, 28, 8, 20, tzinfo=timezone.utc),
        point_count=5,
    )
    return place


def test_route_analytics_are_aggregated_by_postgis(
    mobile_session, django_assert_num_queries
):
    user_id = mobile_session["user"]["id"]
    home = HabitualPlace.objects.create(
        user_id=user_id,
        center=Point(9.19, 45.46, srid=4326),
        radius_meters=50,
        state=HabitualPlace.State.CONFIRMED,
        category=HabitualPlace.Category.CASA,
        custom_name="Casa",
    )
    work = HabitualPlace.objects.create(
        user_id=user_id,
        center=Point(9.20, 45.47, srid=4326),
        radius_meters=50,
        state=HabitualPlace.State.CONFIRMED,
        category=HabitualPlace.Category.LAVORO,
        custom_name="Ufficio",
    )

    def create_trip(sequence, origin, destination, *, started_at=None):
        started_at = started_at or datetime(
            2026, 9, sequence, 8, tzinfo=timezone.utc
        )
        return Trip.objects.create(
            user_id=user_id,
            device_id=f"route-test-{sequence}",
            status=Trip.Status.PROCESSED,
            started_at=started_at,
            ended_at=started_at + timedelta(minutes=20),
            path=LineString(origin, destination, srid=4326),
        )

    old_trip = create_trip(
        5,
        home.center.coords,
        work.center.coords,
        started_at=datetime(2024, 1, 2, 8, tzinfo=timezone.utc),
    )
    pathless_trip = Trip.objects.create(
        user_id=user_id,
        device_id="route-test-pathless",
        status=Trip.Status.PROCESSED,
        started_at=datetime(2023, 6, 14, 8, tzinfo=timezone.utc),
        ended_at=datetime(2023, 6, 14, 8, 20, tzinfo=timezone.utc),
        path=None,
    )
    recent_trips = [
        create_trip(1, home.center.coords, work.center.coords),
        create_trip(2, home.center.coords, work.center.coords),
        create_trip(3, work.center.coords, home.center.coords),
        create_trip(4, home.center.coords, home.center.coords),
    ]

    with django_assert_num_queries(1):
        routes = frequent_routes(user_id)

    assert [
        (route.origin_label, route.destination_label, route.trip_count)
        for route in routes
    ] == [
        ("Casa", "Ufficio", 3),
        ("Ufficio", "Casa", 1),
    ]

    with django_assert_num_queries(1):
        heatmaps = weekly_heatmaps(user_id, ZoneInfo("Europe/Rome"))

    assert [heatmap.label for heatmap in heatmaps] == [
        "12/06/23",
        "01/01/24",
        "31/08/26",
    ]
    assert heatmaps[0].trip_ids == [pathless_trip.id]
    assert heatmaps[0].habitual_places == []
    assert heatmaps[1].trip_ids == [old_trip.id]
    assert [point.weight for point in heatmaps[1].habitual_places] == [1.0, 1.0]
    assert heatmaps[2].trip_ids == [trip.id for trip in recent_trips]
    assert [point.weight for point in heatmaps[2].habitual_places] == [4.0, 3.0]


def test_place_review_exposes_evidence_but_blocks_changes_until_mining_succeeds(
    api_client, mobile_session
):
    headers = mobile_session["headers"]
    place = create_candidate_place(mobile_session["user"]["id"])

    listed = api_client.get("/api/mobility/places", HTTP_AUTHORIZATION=headers["HTTP_AUTHORIZATION"])
    blocked = post_json(
        api_client,
        f"/api/mobility/places/{place.id}/confirm",
        {},
        headers,
    )

    assert listed.status_code == 200
    assert listed.json()[0]["state"] == "CANDIDATE"
    assert listed.json()[0]["visits"][0]["point_count"] == 5
    assert blocked.status_code == 409
    assert blocked.json() == {
        "detail": "analisi dei luoghi abituali non completata",
        "code": "place_mining_not_ready",
        "status": "IDLE",
    }


def test_place_can_be_confirmed_labeled_rejected_and_reactivated(
    api_client, mobile_session
):
    headers = mobile_session["headers"]
    user_id = mobile_session["user"]["id"]
    place = create_candidate_place(user_id)
    PlaceMiningStatus.objects.create(
        user_id=user_id,
        status=PlaceMiningStatus.Status.SUCCEEDED,
    )

    confirmed = post_json(
        api_client,
        f"/api/mobility/places/{place.id}/confirm",
        {},
        headers,
    )
    labeled = post_json(
        api_client,
        f"/api/mobility/places/{place.id}/label",
        {"category": "casa", "custom_name": "Casa Milano"},
        headers,
    )
    rejected = post_json(
        api_client,
        f"/api/mobility/places/{place.id}/reject",
        {},
        headers,
    )
    reactivated = post_json(
        api_client,
        f"/api/mobility/places/{place.id}/reactivate",
        {},
        headers,
    )

    assert confirmed.json()["state"] == "CONFIRMED"
    assert labeled.json()["label"] == "Casa Milano"
    assert labeled.json()["category"] == "casa"
    assert rejected.json()["state"] == "REJECTED"
    assert reactivated.json()["state"] == "CANDIDATE"


def test_place_review_is_isolated_between_owners(
    api_client, mobile_session, register_mobile_user
):
    place = create_candidate_place(mobile_session["user"]["id"])
    other = register_mobile_user("place-other@example.com").json()
    other_headers = {
        "HTTP_AUTHORIZATION": f"Bearer {other['access_token']}"
    }
    PlaceMiningStatus.objects.create(
        user_id=other["user"]["id"],
        status=PlaceMiningStatus.Status.SUCCEEDED,
    )

    response = post_json(
        api_client,
        f"/api/mobility/places/{place.id}/confirm",
        {},
        other_headers,
    )

    assert api_client.get("/api/mobility/places", HTTP_AUTHORIZATION=other_headers["HTTP_AUTHORIZATION"]).json() == []
    assert response.status_code == 404


def test_diary_and_analytics_expose_enriched_segments_through_public_apis(
    api_client, mobile_session
):
    headers = mobile_session["headers"]
    upload_id = start_recording(api_client, headers).json()["upload_id"]
    trip_id = complete_core(api_client, headers, upload_id).json()["trip_id"]
    trip = Trip.objects.get(id=trip_id)
    start = datetime(2026, 8, 30, 10, 0, tzinfo=timezone.utc)
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.MOVE,
        start_timestamp=start,
        end_timestamp=start + timedelta(minutes=10),
        activity_label="WALKING",
        distance_meters=650,
        path=LineString(
            (9.1900, 45.4642),
            (9.1950, 45.4680),
            srid=4326,
        ),
    )

    diary = api_client.get(f"/api/mobility/trips/{trip_id}/diary", HTTP_AUTHORIZATION=headers["HTTP_AUTHORIZATION"])
    analytics = api_client.get(
        "/api/mobility/analytics?granularity=day", HTTP_AUTHORIZATION=headers["HTTP_AUTHORIZATION"]
    )

    assert diary.status_code == 200
    assert diary.json()["segments"] == [
        {
            "kind": "MOVE",
            "start_timestamp": "2026-08-30T10:00:00Z",
            "end_timestamp": "2026-08-30T10:10:00Z",
            "activity_label": "WALKING",
            "distance_meters": 650.0,
            "path_geojson": {
                "type": "LineString",
                "coordinates": [[9.19, 45.4642], [9.195, 45.468]],
            },
            "place": None,
        }
    ]
    assert analytics.status_code == 200
    assert analytics.json()["has_data"] is True
    walking = next(
        category
        for category in analytics.json()["buckets"][0]["categories"]
        if category["category"] == "WALKING"
    )
    assert walking == {"category": "WALKING", "seconds": 600.0, "distance_meters": 650.0}
