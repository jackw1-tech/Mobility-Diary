import json
from datetime import datetime, timedelta, timezone

import pytest
from django.contrib.gis.geos import LineString, Point

from mobility.models import (
    CandidateVisit,
    HabitualPlace,
    MobilitySegment,
    PlaceMiningStatus,
    Trip,
)

from .test_ingestion_and_trips_api import complete_core, post_json, start_recording


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


def test_place_review_exposes_evidence_but_blocks_changes_until_mining_succeeds(
    api_client, mobile_session
):
    headers = mobile_session["headers"]
    place = create_candidate_place(mobile_session["user"]["id"])

    listed = api_client.get("/api/mobility/places", **headers)
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

    assert api_client.get("/api/mobility/places", **other_headers).json() == []
    assert response.status_code == 404


def test_diary_and_analytics_expose_enriched_segments_through_public_apis(
    api_client, mobile_session
):
    headers = mobile_session["headers"]
    ingestion_id = start_recording(api_client, headers).json()["ingestion_id"]
    trip_id = complete_core(api_client, headers, ingestion_id).json()["trip_id"]
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

    diary = api_client.get(f"/api/mobility/trips/{trip_id}/diary", **headers)
    analytics = api_client.get(
        "/api/mobility/analytics?granularity=day&tz=UTC", **headers
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
        if category["category"] == "a_piedi"
    )
    assert walking == {"category": "a_piedi", "seconds": 600.0, "distance_meters": 650.0}
