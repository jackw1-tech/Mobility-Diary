from datetime import timedelta

import pytest
from django.contrib.auth import get_user_model
from django.contrib.gis.geos import LineString, Point
from django.test import Client
from django.utils import timezone

from accounts.models import AccessToken, UserPrivacySettings
from mobility.models import (
    ActivityLabel,
    GpsPoint,
    HabitualPlace,
    MobilitySegment,
    Trip,
    VirtualStopInterval,
)


@pytest.fixture
def user(db):
    return get_user_model().objects.create_user(
        username="export-owner@example.com",
        email="export-owner@example.com",
        password="password",
    )


@pytest.fixture
def other_user(db):
    return get_user_model().objects.create_user(
        username="export-other@example.com",
        email="export-other@example.com",
        password="password",
    )


def auth_headers(user):
    raw_token, _ = AccessToken.issue_for_user(user)
    return {"HTTP_AUTHORIZATION": f"Bearer {raw_token}"}


def _confirmed_place(user, lon, lat, **kwargs):
    return HabitualPlace.objects.create(
        user=user,
        center=Point(lon, lat, srid=4326),
        state=HabitualPlace.State.CONFIRMED,
        **kwargs,
    )


def _add_gps(trip, timestamp, lon, lat, *, speed=0.0):
    GpsPoint.objects.create(
        trip=trip,
        timestamp=timestamp,
        point=Point(lon, lat, srid=4326),
        speed_mps=speed,
    )


def make_diary_trip(user, *, session: str) -> Trip:
    trip = Trip.objects.create(
        user=user,
        client_session_id=session,
        device_id="test-device",
        status=Trip.Status.PROCESSED,
    )
    base = timezone.now()
    _confirmed_place(user, 9.20, 45.47, radius_meters=45, category="universita")
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.MOVE,
        start_timestamp=base,
        end_timestamp=base + timedelta(minutes=10),
        activity_label=ActivityLabel.WALKING,
        path=LineString((9.10, 45.46), (9.20, 45.47), srid=4326),
        distance_meters=1200,
    )
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.STOP,
        start_timestamp=base + timedelta(minutes=10),
        end_timestamp=base + timedelta(minutes=20),
        activity_label=ActivityLabel.IDLE,
    )
    _add_gps(trip, base + timedelta(minutes=12), 9.2000, 45.4700)
    _add_gps(trip, base + timedelta(minutes=16), 9.2001, 45.4701)
    return trip


@pytest.mark.django_db
def test_privacy_export_defaults_to_precise_unprotected(user):
    trip = make_diary_trip(user, session="export-precise")

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/privacy-export",
        **auth_headers(user),
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["level"] == UserPrivacySettings.Level.PRECISE
    assert payload["protected"] is False
    assert payload["approximated_coordinates"] is False
    assert payload["cell_size_meters"] is None
    move, stop = payload["segments"]
    assert move["coordinates"] == [[9.1, 45.46], [9.2, 45.47]]
    assert stop["title"] == "universita"
    assert "NON protetta" in payload["text"]
    assert "universita" in payload["text"]


@pytest.mark.django_db
def test_privacy_export_uses_saved_level_and_masks_non_precise(user):
    UserPrivacySettings.objects.create(
        user=user,
        level=UserPrivacySettings.Level.APPROXIMATE,
        is_first_login=False,
    )
    trip = make_diary_trip(user, session="export-approx")

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/privacy-export",
        **auth_headers(user),
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["level"] == UserPrivacySettings.Level.APPROXIMATE
    assert payload["protected"] is True
    assert payload["approximated_coordinates"] is True
    assert payload["cell_size_meters"] == 150

    move, stop = payload["segments"]
    # Non-precise geometry must be cloaked, never the original GPS readings.
    assert move["coordinates"] != [[9.1, 45.46], [9.2, 45.47]]
    assert stop["title"] != "universita"
    assert stop["title"] == "Sosta significativa in area approssimata"

    text = payload["text"]
    assert "Privacy level: approximate" in text
    assert "Cell size: 150 m" in text
    assert "approximated points" in text
    # No sensitive label and no precise coordinate leaks into the export text.
    assert "universita" not in text
    assert "[9.1, 45.46]" not in text


@pytest.mark.django_db
def test_privacy_export_does_not_change_saved_preference(user):
    UserPrivacySettings.objects.create(
        user=user,
        level=UserPrivacySettings.Level.AGGREGATED,
        is_first_login=False,
    )
    trip = make_diary_trip(user, session="export-aggregated")

    Client().get(
        f"/api/mobility/trips/{trip.id}/privacy-export",
        **auth_headers(user),
    )

    user.refresh_from_db()
    assert user.privacy_settings.level == UserPrivacySettings.Level.AGGREGATED


@pytest.mark.django_db
def test_privacy_export_returns_404_for_other_user(user, other_user):
    trip = make_diary_trip(user, session="export-scoped")

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/privacy-export",
        **auth_headers(other_user),
    )

    assert response.status_code == 404


@pytest.mark.django_db
def test_privacy_export_projects_virtual_stop_with_same_visible_timeline_as_diary(user):
    trip = Trip.objects.create(
        user=user,
        client_session_id="export-virtual-stop",
        device_id="test-device",
        status=Trip.Status.PROCESSED,
    )
    base = timezone.now()
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.MOVE,
        start_timestamp=base,
        end_timestamp=base + timedelta(minutes=10),
        activity_label=ActivityLabel.WALKING,
        path=LineString((9.10, 45.46), (9.20, 45.47), srid=4326),
        distance_meters=1200,
    )
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.MOVE,
        start_timestamp=base + timedelta(minutes=20),
        end_timestamp=base + timedelta(minutes=30),
        activity_label=ActivityLabel.BIKING,
        path=LineString((9.20, 45.47), (9.30, 45.48), srid=4326),
        distance_meters=900,
    )
    VirtualStopInterval.objects.create(
        trip=trip,
        start_timestamp=base + timedelta(minutes=10),
        end_timestamp=base + timedelta(minutes=20),
    )

    diary = Client().get(
        f"/api/mobility/trips/{trip.id}/diary",
        **auth_headers(user),
    )
    export = Client().get(
        f"/api/mobility/trips/{trip.id}/privacy-export",
        **auth_headers(user),
    )

    assert diary.status_code == 200
    assert export.status_code == 200
    diary_segments = diary.json()["segments"]
    export_segments = export.json()["segments"]
    assert [segment["kind"] for segment in export_segments] == [
        segment["kind"] for segment in diary_segments
    ] == [
        MobilitySegment.Kind.MOVE,
        MobilitySegment.Kind.STOP,
        MobilitySegment.Kind.MOVE,
    ]
    stop = export_segments[1]
    assert stop["start_label"] == (base + timedelta(minutes=10)).strftime("%H:%M")
    assert stop["end_label"] == (base + timedelta(minutes=20)).strftime("%H:%M")
    assert stop["title"] == "Sosta rilevata"
    assert "Sosta rilevata" in export.json()["text"]


@pytest.mark.django_db
def test_privacy_export_keeps_one_labeled_stop_after_real_and_virtual_merge(user):
    trip = make_diary_trip(user, session="export-merged-labeled-stop")
    stop = trip.segments.get(kind=MobilitySegment.Kind.STOP)
    VirtualStopInterval.objects.create(
        trip=trip,
        start_timestamp=stop.end_timestamp,
        end_timestamp=stop.end_timestamp + timedelta(minutes=5),
    )

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/privacy-export",
        **auth_headers(user),
    )

    assert response.status_code == 200
    payload = response.json()
    assert len(payload["segments"]) == 2
    merged_stop = payload["segments"][1]
    assert merged_stop["title"] == "universita"
    assert merged_stop["start_label"] == stop.start_timestamp.strftime("%H:%M")
    assert merged_stop["end_label"] == (
        stop.end_timestamp + timedelta(minutes=5)
    ).strftime("%H:%M")
