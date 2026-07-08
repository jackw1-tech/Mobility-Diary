from datetime import datetime, timedelta, timezone as dt_timezone

import pytest
from django.contrib.auth import get_user_model
from django.contrib.gis.geos import LineString, Point
from django.test import Client

from accounts.models import AccessToken, UserPrivacySettings
from mobility.diary_export import build_trip_privacy_export
from mobility.models import ActivityLabel, GpsPoint, HabitualPlace, MobilitySegment, Trip


@pytest.fixture
def mobile_user(db):
    return get_user_model().objects.create_user(
        username="diary-export@example.com",
        email="diary-export@example.com",
        password="password-123",
    )


def _confirmed_place(user, lon, lat, **kwargs):
    return HabitualPlace.objects.create(
        user=user,
        center=Point(lon, lat, srid=4326),
        state=HabitualPlace.State.CONFIRMED,
        **kwargs,
    )


def _add_gps(trip, timestamp, lon, lat):
    return GpsPoint.objects.create(
        trip=trip,
        timestamp=timestamp,
        point=Point(lon, lat, srid=4326),
        speed_mps=0,
        accuracy_meters=5,
    )


def _auth_headers(user) -> dict:
    raw_token, _access_token = AccessToken.issue_for_user(user)
    return {"HTTP_AUTHORIZATION": f"Bearer {raw_token}"}


def _sample_trip(user):
    base = datetime(2026, 1, 1, 8, 1, tzinfo=dt_timezone.utc)
    trip = Trip.objects.create(
        user=user,
        client_session_id="diary-export-trip",
        device_id="test-device",
        status=Trip.Status.PROCESSED,
        started_at=base,
        ended_at=base + timedelta(hours=1, minutes=9),
    )
    _confirmed_place(
        user,
        9.1000,
        45.4600,
        radius_meters=25,
        category=HabitualPlace.Category.CASA,
        custom_name="Casa",
    )
    _confirmed_place(
        user,
        9.1200,
        45.4700,
        radius_meters=35,
        category=HabitualPlace.Category.UNIVERSITA,
        custom_name="Universita",
    )
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.STOP,
        start_timestamp=base,
        end_timestamp=base + timedelta(minutes=10),
        activity_label=ActivityLabel.IDLE,
    )
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.MOVE,
        start_timestamp=base + timedelta(minutes=10),
        end_timestamp=base + timedelta(minutes=30),
        activity_label=ActivityLabel.BIKING,
        path=LineString((9.1000, 45.4600), (9.1200, 45.4700), srid=4326),
        distance_meters=2000,
    )
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.STOP,
        start_timestamp=base + timedelta(minutes=30),
        end_timestamp=base + timedelta(hours=1, minutes=9),
        activity_label=ActivityLabel.IDLE,
    )
    _add_gps(trip, base + timedelta(minutes=2), 9.1000, 45.4600)
    _add_gps(trip, base + timedelta(minutes=8), 9.1001, 45.4601)
    _add_gps(trip, base + timedelta(minutes=35), 9.1200, 45.4700)
    _add_gps(trip, base + timedelta(minutes=55), 9.1201, 45.4701)
    return trip


@pytest.mark.django_db
def test_precise_export_is_a_detailed_mobility_diary(mobile_user):
    trip = _sample_trip(mobile_user)

    export = build_trip_privacy_export(
        trip,
        level=UserPrivacySettings.Level.PRECISE,
    )

    assert export.protected is False
    assert export.approximated_coordinates is False
    assert export.cell_size_meters is None
    assert [segment.title for segment in export.segments] == [
        "Casa",
        "in bici",
        "Universita",
    ]
    assert "Vista: dettagliata" in export.text
    assert "08:01-08:11, permanenza in Casa, durata: 10m" in export.text
    assert (
        "08:11-08:31, spostamento da Casa a Universita, "
        "modalita' prevalente: in bici, distanza: 2.0 km"
    ) in export.text
    assert "08:31-09:10, permanenza in Universita, durata: 39m" in export.text


@pytest.mark.django_db
def test_approximate_export_keeps_the_story_but_masks_places_and_path(mobile_user):
    trip = _sample_trip(mobile_user)

    export = build_trip_privacy_export(
        trip,
        level=UserPrivacySettings.Level.APPROXIMATE,
    )

    assert export.protected is True
    assert export.approximated_coordinates is True
    assert export.cell_size_meters == 150
    assert [segment.title for segment in export.segments] == [
        "area residenziale",
        "in bici",
        "zona universitaria",
    ]
    move = export.segments[1]
    assert move.coordinates != [[9.1, 45.46], [9.12, 45.47]]
    assert "Vista: condivisibile approssimata" in export.text
    assert "Cloaking spaziale: celle da 150 m" in export.text
    assert "Casa" not in export.text
    assert "Universita" not in export.text
    assert "08:00-08:15, permanenza in area residenziale, durata: 15m" in export.text
    assert (
        "08:10-08:35, spostamento da area residenziale a zona universitaria, "
        "modalita' prevalente: in bici"
    ) in export.text


@pytest.mark.django_db
def test_aggregated_export_summarizes_patterns_without_places_or_paths(mobile_user):
    trip = _sample_trip(mobile_user)

    export = build_trip_privacy_export(
        trip,
        level=UserPrivacySettings.Level.AGGREGATED,
    )

    assert export.protected is True
    assert export.approximated_coordinates is True
    assert export.cell_size_meters == 400
    assert [segment.title for segment in export.segments] == [
        "mattina: movimento aggregato",
        "mattina: permanenza aggregata",
    ]
    assert all(segment.coordinates == [] for segment in export.segments)
    assert all(segment.point_count == 0 for segment in export.segments)
    assert "Vista: aggregata" in export.text
    assert "Percorsi e luoghi puntuali non sono inclusi." in export.text
    assert "mattina: movimento aggregato: 25m" in export.text
    assert "mattina: permanenza aggregata: 55m" in export.text
    assert "- tempo in movimento: 25m" in export.text
    assert "- tempo in sosta: 55m" in export.text
    assert "- aree significative visitate: 2" in export.text
    assert "Casa" not in export.text
    assert "Universita" not in export.text
    assert "area residenziale" not in export.text
    assert "zona universitaria" not in export.text


@pytest.mark.django_db
def test_privacy_export_endpoint_uses_the_centralized_diary_export(mobile_user):
    trip = _sample_trip(mobile_user)
    UserPrivacySettings.objects.update_or_create(
        user=mobile_user,
        defaults={
            "level": UserPrivacySettings.Level.APPROXIMATE,
            "is_first_login": False,
        },
    )

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/privacy-export",
        **_auth_headers(mobile_user),
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["level"] == UserPrivacySettings.Level.APPROXIMATE
    assert payload["protected"] is True
    assert payload["approximated_coordinates"] is True
    assert payload["segments"][0]["title"] == "area residenziale"
    assert payload["segments"][2]["title"] == "zona universitaria"
    assert "Vista: condivisibile approssimata" in payload["text"]
