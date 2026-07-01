from datetime import timedelta

import pytest
from django.contrib.auth import get_user_model
from django.contrib.gis.geos import Point
from django.test import Client
from django.utils import timezone

from accounts.models import AccessToken
from mobility.models import (
    GpsPoint,
    PartKind,
    SensorWindow,
    Trip,
    TripIngestion,
    TripIngestionPart,
)
from mobility.tasks import _build_trip_path


@pytest.fixture
def user(db):
    return get_user_model().objects.create_user(
        username="owner@example.com",
        email="owner@example.com",
        password="password",
    )


@pytest.fixture
def other_user(db):
    return get_user_model().objects.create_user(
        username="other@example.com",
        email="other@example.com",
        password="password",
    )


def auth_headers(user):
    raw_token, _ = AccessToken.issue_for_user(user)
    return {"HTTP_AUTHORIZATION": f"Bearer {raw_token}"}


def make_trip(user, *, client_session_id, started_at) -> Trip:
    trip = Trip.objects.create(
        user=user,
        client_session_id=client_session_id,
        device_id="test-device",
        status=Trip.Status.CLOSED,
    )
    # started_at e' auto_now_add: lo forzo per testare l'ordinamento.
    Trip.objects.filter(pk=trip.pk).update(started_at=started_at)
    trip.refresh_from_db()
    return trip


def add_completed_ingestion(user, trip):
    return TripIngestion.objects.create(
        user=user,
        trip=trip,
        client_session_id=f"ingestion-{trip.id}",
        core_status=TripIngestion.PhaseStatus.COMPLETED,
        raw_status=TripIngestion.PhaseStatus.COMPLETED,
    )


@pytest.mark.django_db
def test_list_trips_returns_user_trips_newest_first_with_track_flag(user):
    now = timezone.now()
    older = make_trip(user, client_session_id="a", started_at=now - timedelta(hours=2))
    newer = make_trip(user, client_session_id="b", started_at=now)

    # Solo "newer" ha una traiettoria disegnabile.
    GpsPoint.objects.create(
        trip=newer, timestamp=now, point=Point(9.1, 45.4, srid=4326), speed_mps=1.0
    )
    GpsPoint.objects.create(
        trip=newer,
        timestamp=now + timedelta(minutes=1),
        point=Point(9.2, 45.5, srid=4326),
        speed_mps=1.0,
    )
    _build_trip_path(newer)

    response = Client().get("/api/mobility/trips", **auth_headers(user))

    assert response.status_code == 200
    payload = response.json()
    assert [t["id"] for t in payload] == [newer.id, older.id]
    assert payload[0]["has_track"] is True
    assert payload[0]["distance_meters"] > 0
    assert payload[0]["note"] == ""
    assert payload[0]["can_edit_note"] is False
    assert payload[1]["has_track"] is False


@pytest.mark.django_db
def test_list_trips_excludes_other_users_trips(user, other_user):
    make_trip(user, client_session_id="mine", started_at=timezone.now())
    make_trip(other_user, client_session_id="theirs", started_at=timezone.now())

    response = Client().get("/api/mobility/trips", **auth_headers(user))

    assert response.status_code == 200
    payload = response.json()
    assert len(payload) == 1
    assert payload[0]["status"] == Trip.Status.CLOSED


@pytest.mark.django_db
def test_list_trips_ignores_abandoned_ingestions_without_visible_trip(user):
    now = timezone.now()
    visible = make_trip(user, client_session_id="visible", started_at=now)
    TripIngestion.objects.create(
        user=user,
        client_session_id="abandoned-recording",
        device_id="test-device",
        recording_started_at=now - timedelta(minutes=10),
        recording_abandoned_at=now,
    )

    response = Client().get("/api/mobility/trips", **auth_headers(user))

    assert response.status_code == 200
    assert [trip["id"] for trip in response.json()] == [visible.id]


@pytest.mark.django_db
def test_list_trips_requires_auth():
    response = Client().get("/api/mobility/trips")
    assert response.status_code == 401


@pytest.mark.django_db
def test_list_reloadable_trips_returns_only_published_completed_sources(
    user, other_user
):
    now = timezone.now()
    published = make_trip(
        user,
        client_session_id="published",
        started_at=now - timedelta(minutes=30),
    )
    unpublished = make_trip(
        user,
        client_session_id="unpublished",
        started_at=now - timedelta(minutes=20),
    )
    open_published = make_trip(
        user,
        client_session_id="open-published",
        started_at=now - timedelta(minutes=10),
    )
    other_published = make_trip(
        other_user,
        client_session_id="other-published",
        started_at=now - timedelta(minutes=5),
    )
    Trip.objects.filter(pk=published.pk).update(is_reloadable=True)
    Trip.objects.filter(pk=open_published.pk).update(
        is_reloadable=True,
        status=Trip.Status.OPEN,
    )
    Trip.objects.filter(pk=other_published.pk).update(is_reloadable=True)

    response = Client().get("/api/mobility/trips/reloadable", **auth_headers(user))

    assert response.status_code == 200
    payload = response.json()
    assert [trip["id"] for trip in payload] == [published.id]
    assert payload[0]["status"] == Trip.Status.CLOSED
    assert unpublished.id not in [trip["id"] for trip in payload]
    assert open_published.id not in [trip["id"] for trip in payload]
    assert other_published.id not in [trip["id"] for trip in payload]


@pytest.mark.django_db
def test_list_reloadable_trips_requires_auth():
    response = Client().get("/api/mobility/trips/reloadable")
    assert response.status_code == 401


@pytest.mark.django_db
def test_can_publish_real_trip_with_raw_sensor_evidence(user):
    now = timezone.now()
    trip = make_trip(user, client_session_id="real", started_at=now)
    ingestion = TripIngestion.objects.create(
        user=user,
        trip=trip,
        client_session_id="real",
        raw_status=TripIngestion.PhaseStatus.COMPLETED,
    )
    TripIngestionPart.objects.create(
        ingestion=ingestion,
        kind=PartKind.SENSOR_WINDOWS,
        sequence=1,
        sha256="abc",
        object_key="ingestions/1/sensor_windows_0001.json.gz",
        received_at=now,
    )

    response = Client().patch(
        f"/api/mobility/trips/{trip.id}/reloadable",
        data={"is_reloadable": True},
        content_type="application/json",
        **auth_headers(user),
    )

    trip.refresh_from_db()
    assert response.status_code == 200
    assert trip.is_reloadable is True
    assert response.json()["is_reloadable"] is True
    assert response.json()["can_toggle_reloadable"] is True


@pytest.mark.django_db
def test_can_update_note_only_after_core_and_raw_completed(user):
    now = timezone.now()
    trip = make_trip(user, client_session_id="note", started_at=now)
    response_before = Client().patch(
        f"/api/mobility/trips/{trip.id}/note",
        data={"note": "Casa universita"},
        content_type="application/json",
        **auth_headers(user),
    )
    add_completed_ingestion(user, trip)

    response_after = Client().patch(
        f"/api/mobility/trips/{trip.id}/note",
        data={"note": "  Casa universita  "},
        content_type="application/json",
        **auth_headers(user),
    )

    trip.refresh_from_db()
    assert response_before.status_code == 409
    assert response_after.status_code == 200
    assert trip.note == "Casa universita"
    assert response_after.json()["note"] == "Casa universita"
    assert response_after.json()["can_edit_note"] is True


@pytest.mark.django_db
def test_note_can_be_cleared(user):
    now = timezone.now()
    trip = make_trip(user, client_session_id="clear-note", started_at=now)
    add_completed_ingestion(user, trip)
    Trip.objects.filter(pk=trip.pk).update(note="Da svuotare")

    response = Client().patch(
        f"/api/mobility/trips/{trip.id}/note",
        data={"note": ""},
        content_type="application/json",
        **auth_headers(user),
    )

    trip.refresh_from_db()
    assert response.status_code == 200
    assert trip.note == ""


@pytest.mark.django_db
def test_cannot_publish_derived_trip(user, other_user):
    now = timezone.now()
    source = make_trip(other_user, client_session_id="source", started_at=now)
    derived = make_trip(user, client_session_id="derived", started_at=now)
    Trip.objects.filter(pk=derived.pk).update(reloaded_from_trip=source)

    response = Client().patch(
        f"/api/mobility/trips/{derived.id}/reloadable",
        data={"is_reloadable": True},
        content_type="application/json",
        **auth_headers(user),
    )

    derived.refresh_from_db()
    assert response.status_code == 409
    assert derived.is_reloadable is False


@pytest.mark.django_db
def test_cannot_withdraw_reloadable_after_it_was_cloned(user, other_user):
    now = timezone.now()
    source = make_trip(user, client_session_id="source", started_at=now)
    Trip.objects.filter(pk=source.pk).update(is_reloadable=True)
    make_trip(other_user, client_session_id="derived", started_at=now)
    Trip.objects.filter(client_session_id="derived").update(reloaded_from_trip=source)

    response = Client().patch(
        f"/api/mobility/trips/{source.id}/reloadable",
        data={"is_reloadable": False},
        content_type="application/json",
        **auth_headers(user),
    )

    source.refresh_from_db()
    assert response.status_code == 409
    assert source.is_reloadable is True


@pytest.mark.django_db
def test_delete_trip_removes_database_rows_and_bucket_objects(user, monkeypatch):
    now = timezone.now()
    deleted = []
    trip = make_trip(user, client_session_id="delete-me", started_at=now)
    SensorWindow.objects.create(
        trip=trip,
        start_timestamp=now,
        end_timestamp=now + timedelta(seconds=5),
        sample_count=1,
        frequency_hz=1,
        object_key="legacy/window.json.gz",
    )
    ingestion = TripIngestion.objects.create(
        user=user,
        trip=trip,
        client_session_id="delete-me",
    )
    TripIngestionPart.objects.create(
        ingestion=ingestion,
        kind=PartKind.SENSOR_WINDOWS,
        sequence=1,
        sha256="abc",
        object_key="ingestions/2/sensor_windows_0001.json.gz",
    )
    monkeypatch.setattr("mobility.api.storage.delete_object", deleted.append)

    response = Client().delete(
        f"/api/mobility/trips/{trip.id}",
        **auth_headers(user),
    )

    assert response.status_code == 204
    assert not Trip.objects.filter(id=trip.id).exists()
    assert not TripIngestion.objects.filter(id=ingestion.id).exists()
    assert deleted == [
        "ingestions/2/sensor_windows_0001.json.gz",
        "legacy/window.json.gz",
    ]


@pytest.mark.django_db
def test_delete_trip_is_blocked_after_it_was_cloned(user, other_user, monkeypatch):
    now = timezone.now()
    source = make_trip(user, client_session_id="source", started_at=now)
    derived = make_trip(other_user, client_session_id="derived", started_at=now)
    Trip.objects.filter(pk=derived.pk).update(reloaded_from_trip=source)
    deleted = []
    monkeypatch.setattr("mobility.api.storage.delete_object", deleted.append)

    response = Client().delete(
        f"/api/mobility/trips/{source.id}",
        **auth_headers(user),
    )

    assert response.status_code == 409
    assert Trip.objects.filter(id=source.id).exists()
    assert deleted == []
