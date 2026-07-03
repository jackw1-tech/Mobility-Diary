from datetime import timedelta

import pytest
from django.contrib.auth import get_user_model
from django.contrib.gis.geos import LineString, Point
from django.test import Client
from django.utils import timezone

from accounts.models import AccessToken
from mobility.models import HabitualPlace, MobilitySegment, Trip, TripIngestion


@pytest.fixture
def user(db):
    return get_user_model().objects.create_user(
        username="analytics-owner@example.com",
        email="analytics-owner@example.com",
        password="password",
    )


@pytest.fixture
def other_user(db):
    return get_user_model().objects.create_user(
        username="analytics-other@example.com",
        email="analytics-other@example.com",
        password="password",
    )


def auth_headers(user):
    raw_token, _ = AccessToken.issue_for_user(user)
    return {"HTTP_AUTHORIZATION": f"Bearer {raw_token}"}


def get_analytics(user, **params):
    return Client().get("/api/mobility/analytics", params, **auth_headers(user))


def add_segment(trip, start, minutes, activity, *, distance=0.0, kind="MOVE"):
    return MobilitySegment.objects.create(
        trip=trip,
        kind=kind,
        activity_label=activity,
        start_timestamp=start,
        end_timestamp=start + timedelta(minutes=minutes),
        distance_meters=distance,
    )


def seconds_for(bucket, category):
    slice_ = next(c for c in bucket["categories"] if c["category"] == category)
    return slice_["seconds"]


def add_place(
    user,
    lon,
    lat,
    *,
    visits=0,
    state=HabitualPlace.State.CONFIRMED,
    name="",
    radius=0,
):
    return HabitualPlace.objects.create(
        user=user,
        center=Point(lon, lat, srid=4326),
        state=state,
        visit_count=visits,
        custom_name=name,
        radius_meters=radius,
    )


def add_trip_with_path(user, coords, *, session):
    return Trip.objects.create(
        user=user,
        device_id="d",
        client_session_id=session,
        path=LineString(*coords, srid=4326),
    )


def set_trip_started_at(trip, started_at):
    Trip.objects.filter(pk=trip.pk).update(started_at=started_at)
    trip.refresh_from_db()
    return trip


@pytest.mark.django_db
def test_analytics_empty_history_is_well_formed(user):
    response = get_analytics(user)

    assert response.status_code == 200
    payload = response.json()
    assert payload["has_data"] is False
    assert payload["granularity"] == "day"
    assert payload["buckets"] == []
    assert payload["prevalent_mode"] is None
    assert payload["frequent_routes"] == []
    assert payload["heatmap"] == []
    assert payload["weekly_heatmaps"] == []


@pytest.mark.django_db
def test_buckets_are_empty_without_segments_even_if_a_trip_exists(user):
    # has_data guarda i Trip, i bucket guardano i MobilitySegment: un Trip
    # non ancora processato non deve inventare un bucket vuoto.
    Trip.objects.create(user=user, device_id="d", client_session_id="s")

    payload = get_analytics(user).json()

    assert payload["has_data"] is True
    assert payload["buckets"] == []


@pytest.mark.django_db
def test_analytics_reports_has_data_when_user_has_a_trip(user):
    Trip.objects.create(user=user, device_id="d", client_session_id="s")

    payload = get_analytics(user).json()

    assert payload["has_data"] is True


@pytest.mark.django_db
def test_analytics_is_user_scoped(user, other_user):
    Trip.objects.create(user=other_user, device_id="d", client_session_id="s")

    payload = get_analytics(user).json()

    assert payload["has_data"] is False


@pytest.mark.django_db
def test_analytics_ignores_abandoned_and_failed_final_ingestions(user):
    now = timezone.now()
    TripIngestion.objects.create(
        user=user,
        client_session_id="analytics-abandoned",
        device_id="test-device",
        recording_started_at=now - timedelta(minutes=20),
        recording_abandoned_at=now - timedelta(minutes=5),
    )
    TripIngestion.objects.create(
        user=user,
        client_session_id="analytics-failed-final",
        device_id="test-device",
        core_status=TripIngestion.PhaseStatus.FAILED_FINAL,
        recording_started_at=now - timedelta(minutes=10),
        recording_closed_at=now,
    )

    payload = get_analytics(user).json()

    assert payload["has_data"] is False
    assert payload["heatmap"] == []
    assert payload["weekly_heatmaps"] == []


@pytest.mark.django_db
def test_analytics_echoes_week_granularity_and_defaults_unknown_to_day(user):
    assert get_analytics(user, granularity="week").json()["granularity"] == "week"
    assert get_analytics(user, granularity="bogus").json()["granularity"] == "day"


@pytest.mark.django_db
def test_day_buckets_aggregate_seconds_and_distance_per_category(user):
    trip = Trip.objects.create(user=user, device_id="d", client_session_id="s")
    noon = timezone.now().replace(hour=12, minute=0, second=0, microsecond=0)
    add_segment(trip, noon, 10, "WALKING", distance=1200)
    add_segment(trip, noon, 30, "IDLE", kind="STOP")

    buckets = get_analytics(user, granularity="day", tz="UTC").json()["buckets"]

    # Un solo giorno di attivita': un solo bucket, non piu' una finestra fissa.
    assert len(buckets) == 1
    today = buckets[-1]
    assert [c["category"] for c in today["categories"]] == [
        "fermo",
        "a_piedi",
        "corsa",
        "in_bici",
        "in_auto",
    ]
    assert seconds_for(today, "a_piedi") == 600
    assert seconds_for(today, "fermo") == 1800
    a_piedi = next(c for c in today["categories"] if c["category"] == "a_piedi")
    assert a_piedi["distance_meters"] == 1200


@pytest.mark.django_db
def test_day_buckets_span_the_full_history_including_empty_days(user):
    trip = Trip.objects.create(user=user, device_id="d", client_session_id="s")
    noon = timezone.now().replace(hour=12, minute=0, second=0, microsecond=0)
    add_segment(trip, noon - timedelta(days=9), 10, "WALKING", distance=1200)
    add_segment(trip, noon, 20, "BIKING", distance=500)

    buckets = get_analytics(user, granularity="day", tz="UTC").json()["buckets"]

    # Dal viaggio meno recente al piu' recente: 10 giorni, bucket vuoti inclusi.
    assert len(buckets) == 10
    assert seconds_for(buckets[0], "a_piedi") == 600
    assert seconds_for(buckets[-1], "in_bici") == 1200
    assert all(c["seconds"] == 0 for b in buckets[1:-1] for c in b["categories"])


@pytest.mark.django_db
def test_week_granularity_returns_one_bucket_for_a_single_active_week(user):
    trip = Trip.objects.create(user=user, device_id="d", client_session_id="s")
    noon = timezone.now().replace(hour=12, minute=0, second=0, microsecond=0)
    add_segment(trip, noon, 10, "BIKING", distance=500)

    buckets = get_analytics(user, granularity="week", tz="UTC").json()["buckets"]

    assert len(buckets) == 1
    assert seconds_for(buckets[-1], "in_bici") == 600


@pytest.mark.django_db
def test_week_buckets_span_the_full_history_including_empty_weeks(user):
    trip = Trip.objects.create(user=user, device_id="d", client_session_id="s")
    noon = timezone.now().replace(hour=12, minute=0, second=0, microsecond=0)
    add_segment(trip, noon - timedelta(weeks=3), 10, "WALKING", distance=1200)
    add_segment(trip, noon, 20, "BIKING", distance=500)

    buckets = get_analytics(user, granularity="week", tz="UTC").json()["buckets"]

    assert len(buckets) == 4
    assert seconds_for(buckets[0], "a_piedi") == 600
    assert seconds_for(buckets[-1], "in_bici") == 1200
    assert all(c["seconds"] == 0 for b in buckets[1:-1] for c in b["categories"])


@pytest.mark.django_db
def test_day_buckets_are_capped_against_a_runaway_timestamp(user):
    # Un timestamp anomalo (clock del device sballato, bug di ingestion) non
    # deve far generare bucket per decenni: la Finestra Analitica si ferma a
    # _ANALYTICS_MAX_SPAN dal bucket piu' recente.
    trip = Trip.objects.create(user=user, device_id="d", client_session_id="s")
    noon = timezone.now().replace(hour=12, minute=0, second=0, microsecond=0)
    add_segment(trip, noon, 10, "WALKING", distance=1200)
    add_segment(trip, noon - timedelta(days=20 * 365), 5, "BIKING", distance=50)

    buckets = get_analytics(user, granularity="day", tz="UTC").json()["buckets"]

    assert len(buckets) <= 3651
    assert seconds_for(buckets[-1], "a_piedi") == 600
    # Il bucket vecchio di 20 anni resta fuori dalla Finestra Analitica.
    assert all(seconds_for(b, "in_bici") == 0 for b in buckets)


@pytest.mark.django_db
def test_week_buckets_are_capped_against_a_runaway_timestamp(user):
    trip = Trip.objects.create(user=user, device_id="d", client_session_id="s")
    noon = timezone.now().replace(hour=12, minute=0, second=0, microsecond=0)
    add_segment(trip, noon, 10, "WALKING", distance=1200)
    add_segment(trip, noon - timedelta(days=20 * 365), 5, "BIKING", distance=50)

    buckets = get_analytics(user, granularity="week", tz="UTC").json()["buckets"]

    assert len(buckets) <= 523
    assert seconds_for(buckets[-1], "a_piedi") == 600


@pytest.mark.django_db
def test_segments_are_bucketed_by_local_day_boundary(user):
    trip = Trip.objects.create(user=user, device_id="d", client_session_id="s")
    midnight = timezone.now().replace(hour=0, minute=0, second=0, microsecond=0)
    add_segment(trip, midnight + timedelta(minutes=30), 10, "WALKING")  # oggi 00:30
    add_segment(trip, midnight - timedelta(minutes=30), 20, "BIKING")  # ieri 23:30

    buckets = get_analytics(user, granularity="day", tz="UTC").json()["buckets"]

    assert seconds_for(buckets[-1], "a_piedi") == 600
    assert seconds_for(buckets[-1], "in_bici") == 0
    assert seconds_for(buckets[-2], "in_bici") == 1200


@pytest.mark.django_db
def test_unknown_timezone_falls_back_without_error(user):
    trip = Trip.objects.create(user=user, device_id="d", client_session_id="s")
    add_segment(trip, timezone.now(), 10, "WALKING")

    response = get_analytics(user, granularity="day", tz="Not/AZone")

    assert response.status_code == 200
    assert len(response.json()["buckets"]) == 1


@pytest.mark.django_db
def test_numeric_offset_timezone_is_accepted(user):
    # Il mobile invia l'offset locale in minuti (es. +120 = CEST), non un nome IANA.
    trip = Trip.objects.create(user=user, device_id="d", client_session_id="s")
    add_segment(trip, timezone.now(), 10, "WALKING")

    response = get_analytics(user, granularity="day", tz="120")

    assert response.status_code == 200
    assert len(response.json()["buckets"]) == 1


@pytest.mark.django_db
def test_heatmap_weights_confirmed_places_by_visit_count(user):
    add_place(user, 9.20, 45.47, visits=12)

    heatmap = get_analytics(user).json()["heatmap"]

    assert heatmap == [{"lat": 45.47, "lon": 9.20, "weight": 12.0}]


@pytest.mark.django_db
def test_heatmap_excludes_non_confirmed_places(user):
    add_place(user, 9.20, 45.47, visits=5, state=HabitualPlace.State.CANDIDATE)
    add_place(user, 9.10, 45.46, visits=3, state=HabitualPlace.State.REJECTED)

    assert get_analytics(user).json()["heatmap"] == []


@pytest.mark.django_db
def test_heatmap_is_user_scoped(user, other_user):
    add_place(other_user, 9.20, 45.47, visits=9)

    assert get_analytics(user).json()["heatmap"] == []


@pytest.mark.django_db
def test_weekly_heatmaps_group_trips_and_confirmed_places_by_week(user):
    monday = timezone.now().replace(
        hour=10, minute=0, second=0, microsecond=0
    ) - timedelta(days=timezone.now().weekday())
    add_place(user, 9.10, 45.46, visits=8, name="Casa")
    add_place(user, 9.20, 45.47, visits=5, name="Universita")
    add_place(user, 8.00, 44.00, visits=3, state=HabitualPlace.State.CANDIDATE)
    first = set_trip_started_at(
        add_trip_with_path(user, [(9.10, 45.46), (9.20, 45.47)], session="a"),
        monday + timedelta(hours=8),
    )
    second = set_trip_started_at(
        add_trip_with_path(user, [(9.10, 45.46), (8.00, 44.00)], session="b"),
        monday + timedelta(days=1, hours=9),
    )

    weekly = get_analytics(user, tz="UTC").json()["weekly_heatmaps"]

    current = weekly[-1]
    assert current["label"] == monday.strftime("%d/%m")
    assert current["trip_ids"] == [first.id, second.id]
    assert current["habitual_places"] == [
        {"lat": 45.46, "lon": 9.10, "weight": 2.0},
        {"lat": 45.47, "lon": 9.20, "weight": 1.0},
    ]


@pytest.mark.django_db
def test_prevalent_mode_picks_most_time_excluding_fermo(user):
    trip = Trip.objects.create(user=user, device_id="d", client_session_id="s")
    now = timezone.now()
    add_segment(trip, now, 10, "WALKING")
    add_segment(trip, now, 20, "BIKING")
    add_segment(trip, now, 120, "IDLE", kind="STOP")  # Fermo: ignorato

    assert get_analytics(user).json()["prevalent_mode"] == "in_bici"


@pytest.mark.django_db
def test_prevalent_mode_is_null_without_movement(user):
    trip = Trip.objects.create(user=user, device_id="d", client_session_id="s")
    add_segment(trip, timezone.now(), 30, "IDLE", kind="STOP")

    assert get_analytics(user).json()["prevalent_mode"] is None


@pytest.mark.django_db
def test_frequent_routes_count_origin_destination_pairs(user):
    add_place(user, 9.10, 45.46, name="Casa")
    add_place(user, 9.20, 45.47, name="Universita")
    add_trip_with_path(user, [(9.10, 45.46), (9.20, 45.47)], session="a")
    add_trip_with_path(user, [(9.10, 45.46), (9.20, 45.47)], session="b")
    add_trip_with_path(user, [(9.20, 45.47), (9.10, 45.46)], session="c")

    routes = get_analytics(user).json()["frequent_routes"]

    assert routes == [
        {"origin_label": "Casa", "destination_label": "Universita", "trip_count": 2},
        {"origin_label": "Universita", "destination_label": "Casa", "trip_count": 1},
    ]


@pytest.mark.django_db
def test_frequent_routes_skip_trips_without_matched_endpoints(user):
    add_place(user, 9.10, 45.46, name="Casa")
    add_place(user, 9.20, 45.47, name="Universita")
    add_trip_with_path(user, [(8.0, 44.0), (8.1, 44.1)], session="far")
    # Origine = destinazione (giro ad anello): non e' un percorso tra due luoghi.
    add_trip_with_path(user, [(9.10, 45.46), (9.10, 45.46)], session="loop")

    assert get_analytics(user).json()["frequent_routes"] == []
