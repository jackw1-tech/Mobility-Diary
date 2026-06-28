import asyncio
import json
from datetime import timedelta

import pytest
from asgiref.sync import async_to_sync
from django.contrib.auth import get_user_model
from django.contrib.gis.geos import LineString, Point
from django.test import Client
from django.utils import timezone

from accounts.models import AccessToken
from mobility import api as mobility_api
from mobility.ml.classifier import ClassifierResult
from mobility.ml.pipeline import PipelineSensorWindow, run_pipeline
from mobility.models import (
    ActivityLabel,
    CandidateVisit,
    GpsPoint,
    HabitualPlace,
    MobilitySegment,
    PartKind,
    PlaceMiningStatus,
    StateTransition,
    Trip,
    TripIngestion,
    TripIngestionPart,
    VirtualStopInterval,
)
from mobility.tasks import _build_trip_path, process_trip_ingestion


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


def create_trip(user, *, client_session_id="session-track") -> Trip:
    return Trip.objects.create(
        user=user,
        client_session_id=client_session_id,
        device_id="test-device",
        status=Trip.Status.CLOSED,
    )


def add_gps(trip: Trip, timestamp, lon: float, lat: float) -> GpsPoint:
    return GpsPoint.objects.create(
        trip=trip,
        timestamp=timestamp,
        point=Point(lon, lat, srid=4326),
        speed_mps=1.0,
    )


def _window(start, seconds: int):
    return PipelineSensorWindow(
        start_timestamp=start,
        end_timestamp=start + timedelta(seconds=seconds),
        sample_count=500,
        frequency_hz=100,
        matrix=[[0.0] * 9 for _ in range(500)],
    )


def _api_timestamp(value):
    return value.isoformat(timespec="milliseconds").replace("+00:00", "Z")


@pytest.mark.django_db
def test_build_trip_path_orders_points_by_timestamp(user):
    trip = create_trip(user)
    base = timezone.now()
    add_gps(trip, base + timedelta(minutes=2), 9.30, 45.46)
    add_gps(trip, base, 9.10, 45.46)
    add_gps(trip, base + timedelta(minutes=1), 9.20, 45.46)

    point_count = _build_trip_path(trip)

    trip.refresh_from_db()
    assert point_count == 3
    assert trip.path is not None
    assert trip.distance_meters > 0
    assert list(trip.path.coords) == [
        (9.10, 45.46),
        (9.20, 45.46),
        (9.30, 45.46),
    ]


@pytest.mark.django_db
@pytest.mark.parametrize("point_count", [0, 1])
def test_build_trip_path_keeps_path_empty_for_less_than_two_points(user, point_count):
    trip = create_trip(user, client_session_id=f"empty-{point_count}")
    if point_count:
        add_gps(trip, timezone.now(), 9.19, 45.46)

    returned_count = _build_trip_path(trip)

    trip.refresh_from_db()
    assert returned_count == point_count
    assert trip.path is None
    assert trip.distance_meters == 0


@pytest.mark.django_db
def test_process_trip_ingestion_builds_path_idempotently(monkeypatch, user):
    ingestion = TripIngestion.objects.create(
        user=user,
        client_session_id="ingestion-track",
        device_id="test-device",
        expected_core_parts={"gps_points": 1, "state_transitions": 1},
        expected_raw_parts={},
        raw_status=TripIngestion.PhaseStatus.COMPLETED,
    )
    now = timezone.now()
    TripIngestionPart.objects.create(
        ingestion=ingestion,
        kind=PartKind.GPS_POINTS,
        sequence=1,
        sha256="gps",
        object_key="gps.json.gz",
        received_at=now,
    )
    TripIngestionPart.objects.create(
        ingestion=ingestion,
        kind=PartKind.STATE_TRANSITIONS,
        sequence=1,
        sha256="state",
        object_key="state.json.gz",
        received_at=now,
    )

    def fake_load_json_gz(object_key):
        if object_key == "gps.json.gz":
            return {
                "points": [
                    {
                        "timestamp": (now + timedelta(minutes=2)).isoformat(),
                        "latitude": 45.46,
                        "longitude": 9.30,
                        "speed_mps": 1.0,
                    },
                    {
                        "timestamp": now.isoformat(),
                        "latitude": 45.46,
                        "longitude": 9.10,
                        "speed_mps": 1.0,
                    },
                ]
            }
        return {
            "transitions": [
                {
                    "timestamp": now.isoformat(),
                    "from_state": "STATIONARY",
                    "to_state": "MOVEMENT",
                    "reason": "test",
                }
            ]
        }

    monkeypatch.setattr("mobility.tasks._load_json_gz", fake_load_json_gz)

    first_result = process_trip_ingestion.run(ingestion.id)
    second_result = process_trip_ingestion.run(ingestion.id)

    trip = Trip.objects.get(client_session_id="ingestion-track")
    assert first_result["path_points"] == 2
    assert second_result == {"skipped": "core ingestion already completed"}
    assert GpsPoint.objects.filter(trip=trip).count() == 2
    assert StateTransition.objects.filter(trip=trip).count() == 1
    assert trip.path is not None
    assert list(trip.path.coords) == [(9.10, 45.46), (9.30, 45.46)]


@pytest.mark.django_db
def test_track_endpoint_returns_geojson_distance_and_lon_lat_order(user):
    trip = create_trip(user)
    base = timezone.now()
    add_gps(trip, base, 9.10, 45.46)
    add_gps(trip, base + timedelta(minutes=1), 9.20, 45.47)
    _build_trip_path(trip)
    trip.refresh_from_db()

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/track",
        **auth_headers(user),
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["trip_id"] == trip.id
    assert payload["point_count"] == 2
    assert payload["distance_meters"] > 0
    assert payload["geojson"]["type"] == "LineString"
    assert payload["geojson"]["coordinates"][0] == [9.10, 45.46]
    assert payload["geojson"]["coordinates"][1] == [9.20, 45.47]


@pytest.mark.django_db
def test_track_endpoint_returns_404_for_other_user(user, other_user):
    trip = create_trip(user)
    add_gps(trip, timezone.now(), 9.10, 45.46)

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/track",
        **auth_headers(other_user),
    )

    assert response.status_code == 404


@pytest.mark.django_db
def test_track_endpoint_returns_empty_track_for_trip_without_path(user):
    trip = create_trip(user)
    add_gps(trip, timezone.now(), 9.10, 45.46)

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/track",
        **auth_headers(user),
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["trip_id"] == trip.id
    assert payload["point_count"] == 1
    assert payload["distance_meters"] == 0
    assert payload["geojson"] is None


@pytest.mark.django_db
def test_diary_endpoint_returns_not_yet_enriched_state(user):
    trip = create_trip(user)

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/diary",
        **auth_headers(user),
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["trip_id"] == trip.id
    assert payload["status"] == Trip.Status.CLOSED
    assert payload["processed"] is False
    assert payload["segments"] == []
    assert payload["places"] == []


def _confirmed_place(user, lon, lat, **kwargs):
    return HabitualPlace.objects.create(
        user=user,
        center=Point(lon, lat, srid=4326),
        state=HabitualPlace.State.CONFIRMED,
        **kwargs,
    )


@pytest.mark.django_db
def test_diary_endpoint_overlays_confirmed_place_on_stop(user, other_user):
    trip = create_trip(user)
    trip.status = Trip.Status.PROCESSED
    trip.save(update_fields=["status", "updated_at"])
    base = timezone.now()
    _confirmed_place(user, 9.20, 45.47, category="universita")
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.MOVE,
        start_timestamp=base,
        end_timestamp=base + timedelta(minutes=10),
        activity_label=ActivityLabel.BIKING,
        path=LineString((9.10, 45.46), (9.20, 45.47), srid=4326),
        distance_meters=1200,
    )
    stop = MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.STOP,
        start_timestamp=base + timedelta(minutes=10),
        end_timestamp=base + timedelta(minutes=20),
        activity_label=ActivityLabel.IDLE,
    )
    # GPS della sosta vicino al luogo confermato: abilita l'overlay per prossimita'.
    add_gps(trip, base + timedelta(minutes=12), 9.2001, 45.4701)
    add_gps(trip, base + timedelta(minutes=15), 9.1999, 45.4699)

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/diary",
        **auth_headers(user),
    )
    other_response = Client().get(
        f"/api/mobility/trips/{trip.id}/diary",
        **auth_headers(other_user),
    )

    assert response.status_code == 200
    assert other_response.status_code == 404
    payload = response.json()
    assert payload["processed"] is True
    assert len(payload["segments"]) == 2
    move, stop_out = payload["segments"]
    assert move["kind"] == MobilitySegment.Kind.MOVE
    assert move["activity_label"] == ActivityLabel.BIKING
    assert move["path_geojson"]["coordinates"] == [[9.1, 45.46], [9.2, 45.47]]
    assert move["place"] is None  # i MOVE non vengono mai arricchiti (ADR 0021)
    assert stop_out["kind"] == MobilitySegment.Kind.STOP
    assert stop_out["place"]["label"] == "universita"
    assert stop_out["place"]["category"] == "universita"
    # Overlay read-time: il segmento persistito non viene riscritto.
    stop.refresh_from_db()
    assert not any(field.name == "place" for field in stop._meta.get_fields())


@pytest.mark.django_db
def test_diary_overlay_uses_neutral_wording_for_unlabeled_confirmed_place(user):
    trip = create_trip(user)
    trip.status = Trip.Status.PROCESSED
    trip.save(update_fields=["status", "updated_at"])
    base = timezone.now()
    _confirmed_place(user, 9.20, 45.47)  # confermato ma senza etichetta manuale
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.STOP,
        start_timestamp=base,
        end_timestamp=base + timedelta(minutes=10),
        activity_label=ActivityLabel.IDLE,
    )
    add_gps(trip, base + timedelta(minutes=2), 9.2000, 45.4700)

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/diary",
        **auth_headers(user),
    )

    stop = response.json()["segments"][0]
    assert stop["place"]["label"] == "luogo abituale"
    assert stop["place"]["category"] == ""


@pytest.mark.django_db
def test_diary_overlay_ignores_unconfirmed_places(user):
    trip = create_trip(user)
    trip.status = Trip.Status.PROCESSED
    trip.save(update_fields=["status", "updated_at"])
    base = timezone.now()
    HabitualPlace.objects.create(
        user=user,
        center=Point(9.20, 45.47, srid=4326),
        state=HabitualPlace.State.CANDIDATE,  # non confermato: non arricchisce
        category="universita",
    )
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.STOP,
        start_timestamp=base,
        end_timestamp=base + timedelta(minutes=10),
        activity_label=ActivityLabel.IDLE,
    )
    add_gps(trip, base + timedelta(minutes=2), 9.2000, 45.4700)

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/diary",
        **auth_headers(user),
    )

    stop = response.json()["segments"][0]["place"]
    assert stop["label"] == "Sosta rilevata"
    assert stop["category"] == ""
    assert stop["lat"] == pytest.approx(45.4700)
    assert stop["lon"] == pytest.approx(9.2000)


@pytest.mark.django_db
def test_diary_overlay_picks_closest_confirmed_place(user):
    trip = create_trip(user)
    trip.status = Trip.Status.PROCESSED
    trip.save(update_fields=["status", "updated_at"])
    base = timezone.now()
    _confirmed_place(user, 9.2000, 45.4700, category="universita")  # vicino
    _confirmed_place(user, 9.2005, 45.4705, category="palestra")    # piu' lontano
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.STOP,
        start_timestamp=base,
        end_timestamp=base + timedelta(minutes=10),
        activity_label=ActivityLabel.IDLE,
    )
    add_gps(trip, base + timedelta(minutes=2), 9.2000, 45.4700)

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/diary",
        **auth_headers(user),
    )

    assert response.json()["segments"][0]["place"]["label"] == "universita"


@pytest.mark.django_db
def test_diary_endpoint_merges_consecutive_stop_and_idle_move(user):
    trip = create_trip(user)
    trip.status = Trip.Status.PROCESSED
    trip.save(update_fields=["status", "updated_at"])
    base = timezone.now()
    _confirmed_place(user, 9.20, 45.47, category="universita")
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.STOP,
        start_timestamp=base,
        end_timestamp=base + timedelta(minutes=5),
        activity_label=ActivityLabel.IDLE,
    )
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.MOVE,
        start_timestamp=base + timedelta(minutes=5),
        end_timestamp=base + timedelta(minutes=10),
        activity_label=ActivityLabel.IDLE,
        path=LineString((9.20, 45.47), (9.2001, 45.4701), srid=4326),
        distance_meters=30,
    )
    add_gps(trip, base + timedelta(minutes=2), 9.2000, 45.4700)

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/diary",
        **auth_headers(user),
    )

    assert response.status_code == 200
    payload = response.json()
    assert len(payload["segments"]) == 1
    stop = payload["segments"][0]
    assert stop["kind"] == MobilitySegment.Kind.STOP
    assert stop["activity_label"] == ActivityLabel.IDLE
    assert stop["path_geojson"] is None
    assert stop["distance_meters"] == 0
    assert stop["place"]["label"] == "universita"


@pytest.mark.django_db
def test_diary_endpoint_projects_virtual_stop_between_moves_without_place(user):
    trip = create_trip(user, client_session_id="virtual-stop-neutral")
    trip.status = Trip.Status.PROCESSED
    trip.save(update_fields=["status", "updated_at"])
    base = timezone.now()
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.MOVE,
        start_timestamp=base,
        end_timestamp=base + timedelta(minutes=5),
        activity_label=ActivityLabel.BIKING,
        path=LineString((9.10, 45.46), (9.15, 45.47), srid=4326),
        distance_meters=600,
    )
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.MOVE,
        start_timestamp=base + timedelta(minutes=10),
        end_timestamp=base + timedelta(minutes=15),
        activity_label=ActivityLabel.WALKING,
        path=LineString((9.15, 45.47), (9.20, 45.48), srid=4326),
        distance_meters=500,
    )
    VirtualStopInterval.objects.create(
        trip=trip,
        start_timestamp=base + timedelta(minutes=5),
        end_timestamp=base + timedelta(minutes=10),
    )
    add_gps(trip, base + timedelta(minutes=6), 9.1500, 45.4700)
    add_gps(trip, base + timedelta(minutes=8), 9.1501, 45.4701)

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/diary",
        **auth_headers(user),
    )

    assert response.status_code == 200
    payload = response.json()
    assert [segment["kind"] for segment in payload["segments"]] == [
        MobilitySegment.Kind.MOVE,
        MobilitySegment.Kind.STOP,
        MobilitySegment.Kind.MOVE,
    ]
    stop = payload["segments"][1]
    assert stop["activity_label"] == ActivityLabel.IDLE
    assert stop["path_geojson"] is None
    assert stop["distance_meters"] == 0
    assert stop["place"]["label"] == "Sosta rilevata"
    assert stop["place"]["category"] == ""
    assert stop["place"]["lat"] == pytest.approx(45.47005)
    assert stop["place"]["lon"] == pytest.approx(9.15005)


@pytest.mark.django_db
def test_diary_endpoint_overlays_confirmed_place_on_virtual_stop(user):
    trip = create_trip(user, client_session_id="virtual-stop-overlay")
    trip.status = Trip.Status.PROCESSED
    trip.save(update_fields=["status", "updated_at"])
    base = timezone.now()
    _confirmed_place(user, 9.20, 45.47, category="universita")
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.MOVE,
        start_timestamp=base,
        end_timestamp=base + timedelta(minutes=5),
        activity_label=ActivityLabel.BIKING,
        path=LineString((9.10, 45.46), (9.20, 45.47), srid=4326),
        distance_meters=1200,
    )
    VirtualStopInterval.objects.create(
        trip=trip,
        start_timestamp=base + timedelta(minutes=5),
        end_timestamp=base + timedelta(minutes=10),
    )
    add_gps(trip, base + timedelta(minutes=6), 9.2000, 45.4700)
    add_gps(trip, base + timedelta(minutes=8), 9.2001, 45.4701)

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/diary",
        **auth_headers(user),
    )

    assert response.status_code == 200
    stop = response.json()["segments"][1]
    assert stop["kind"] == MobilitySegment.Kind.STOP
    assert stop["place"]["label"] == "universita"
    assert stop["place"]["category"] == "universita"


@pytest.mark.django_db
def test_diary_endpoint_merges_adjacent_real_and_virtual_stop_without_visible_move_idle(user):
    trip = create_trip(user, client_session_id="adjacent-real-virtual-stop")
    trip.status = Trip.Status.PROCESSED
    trip.save(update_fields=["status", "updated_at"])
    base = timezone.now()
    _confirmed_place(user, 9.20, 45.47, category="universita")
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.MOVE,
        start_timestamp=base,
        end_timestamp=base + timedelta(minutes=5),
        activity_label=ActivityLabel.BIKING,
        path=LineString((9.10, 45.46), (9.15, 45.47), srid=4326),
        distance_meters=600,
    )
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.STOP,
        start_timestamp=base + timedelta(minutes=5),
        end_timestamp=base + timedelta(minutes=10),
        activity_label=ActivityLabel.IDLE,
    )
    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.MOVE,
        start_timestamp=base + timedelta(minutes=15),
        end_timestamp=base + timedelta(minutes=20),
        activity_label=ActivityLabel.WALKING,
        path=LineString((9.15, 45.47), (9.20, 45.48), srid=4326),
        distance_meters=500,
    )
    VirtualStopInterval.objects.create(
        trip=trip,
        start_timestamp=base + timedelta(minutes=10),
        end_timestamp=base + timedelta(minutes=15),
    )
    add_gps(trip, base + timedelta(minutes=7), 9.2000, 45.4700)
    add_gps(trip, base + timedelta(minutes=12), 9.2001, 45.4701)

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/diary",
        **auth_headers(user),
    )

    assert response.status_code == 200
    payload = response.json()
    assert [
        (segment["kind"], segment["activity_label"])
        for segment in payload["segments"]
    ] == [
        (MobilitySegment.Kind.MOVE, ActivityLabel.BIKING),
        (MobilitySegment.Kind.STOP, ActivityLabel.IDLE),
        (MobilitySegment.Kind.MOVE, ActivityLabel.WALKING),
    ]
    stop = payload["segments"][1]
    assert stop["start_timestamp"] == _api_timestamp(base + timedelta(minutes=5))
    assert stop["end_timestamp"] == _api_timestamp(base + timedelta(minutes=15))
    assert stop["place"]["label"] == "universita"
    assert not any(
        segment["kind"] == MobilitySegment.Kind.MOVE
        and segment["activity_label"] == ActivityLabel.IDLE
        for segment in payload["segments"]
    )


@pytest.mark.django_db
def test_diary_endpoint_absorbs_initial_short_idle_into_following_move(user, monkeypatch):
    base = timezone.now()
    trip = Trip.objects.create(
        user=user,
        client_session_id="initial-short-idle-visible",
        device_id="test-device",
        status=Trip.Status.CLOSED,
        ended_at=base + timedelta(seconds=120),
    )
    StateTransition.objects.bulk_create(
        [
            StateTransition(
                trip=trip,
                from_state="STATIONARY",
                to_state="MOVEMENT",
                reason="start",
                timestamp=base,
            ),
            StateTransition(
                trip=trip,
                from_state="MOVEMENT",
                to_state="STATIONARY",
                reason="stop",
                timestamp=base + timedelta(seconds=120),
            ),
        ]
    )
    for offset, lon, lat in [
        (0, 9.10, 45.46),
        (60, 9.11, 45.47),
        (119, 9.12, 45.48),
    ]:
        GpsPoint.objects.create(
            trip=trip,
            timestamp=base + timedelta(seconds=offset),
            point=Point(lon, lat, srid=4326),
            speed_mps=2.0,
        )
    monkeypatch.setattr(
        "mobility.ml.pipeline.classify_windows",
        lambda *_args, **_kwargs: ClassifierResult(
            labels=[ActivityLabel.IDLE, ActivityLabel.WALKING],
            summary={"classifier": "fake"},
        ),
    )
    monkeypatch.setattr(
        "mobility.ml.pipeline.correct_idle_with_gps",
        lambda labels, _speeds: labels,
    )

    run_pipeline(
        trip,
        sensor_windows=[
            _window(base, 90),
            _window(base + timedelta(seconds=90), 30),
        ],
    )

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/diary",
        **auth_headers(user),
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["processed"] is True
    assert len(payload["segments"]) == 1
    segment = payload["segments"][0]
    assert segment["kind"] == MobilitySegment.Kind.MOVE
    assert segment["activity_label"] == ActivityLabel.WALKING
    assert segment["start_timestamp"] == _api_timestamp(base)
    assert segment["end_timestamp"] == _api_timestamp(base + timedelta(seconds=120))


@pytest.mark.django_db
def test_places_endpoint_lists_places_with_context_and_evidence(user, other_user):
    place = HabitualPlace.objects.create(
        user=user,
        center=Point(9.19, 45.46, srid=4326),
        radius_meters=30,
        state=HabitualPlace.State.CONFIRMED,
        category="universita",
        visit_count=2,
        distinct_days=2,
    )
    base = timezone.now()
    for day in range(2):
        CandidateVisit.objects.create(
            user=user,
            center=Point(9.19, 45.46, srid=4326),
            started_at=base + timedelta(days=day),
            ended_at=base + timedelta(days=day, minutes=6),
            point_count=4,
            place=place,
        )
    # Un luogo di un altro utente non deve comparire.
    HabitualPlace.objects.create(
        user=other_user,
        center=Point(9.0, 45.0, srid=4326),
        state=HabitualPlace.State.CONFIRMED,
    )

    response = Client().get("/api/mobility/places", **auth_headers(user))

    assert response.status_code == 200
    payload = response.json()
    assert len(payload) == 1
    place_out = payload[0]
    assert place_out["state"] == HabitualPlace.State.CONFIRMED
    assert place_out["label"] == "universita"
    assert place_out["category"] == "universita"
    assert place_out["visit_count"] == 2
    assert place_out["distinct_days"] == 2
    assert len(place_out["visits"]) == 2  # evidenza di mappa
    assert place_out["visits"][0]["point_count"] == 4


@pytest.mark.django_db
def test_places_endpoint_uses_neutral_label_for_unlabeled_confirmed(user):
    HabitualPlace.objects.create(
        user=user,
        center=Point(9.19, 45.46, srid=4326),
        state=HabitualPlace.State.CONFIRMED,
    )

    response = Client().get("/api/mobility/places", **auth_headers(user))

    assert response.json()[0]["label"] == "luogo abituale"


@pytest.mark.django_db
def test_places_status_endpoint_returns_idle_without_record(user):
    response = Client().get("/api/mobility/places/status", **auth_headers(user))

    assert response.status_code == 200
    assert response.json() == {
        "status": PlaceMiningStatus.Status.IDLE,
        "requested_at": None,
        "started_at": None,
        "finished_at": None,
        "error_message": "",
        "rerun_requested": False,
    }


@pytest.mark.django_db
def test_places_status_endpoint_returns_persisted_state(user):
    status = PlaceMiningStatus.objects.create(
        user=user,
        status=PlaceMiningStatus.Status.FAILED,
        requested_at=timezone.now() - timedelta(minutes=5),
        started_at=timezone.now() - timedelta(minutes=4),
        finished_at=timezone.now() - timedelta(minutes=3),
        error_message="boom",
        rerun_requested=True,
    )

    response = Client().get("/api/mobility/places/status", **auth_headers(user))

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == PlaceMiningStatus.Status.FAILED
    assert body["error_message"] == "boom"
    assert body["rerun_requested"] is True
    assert body["requested_at"] is not None
    assert body["started_at"] is not None
    assert body["finished_at"] is not None
    status.refresh_from_db()
    assert status.status == PlaceMiningStatus.Status.FAILED


@pytest.mark.django_db
def test_place_actions_confirm_reject_reactivate_and_label(user):
    place = HabitualPlace.objects.create(
        user=user,
        center=Point(9.19, 45.46, srid=4326),
        state=HabitualPlace.State.CANDIDATE,
    )
    PlaceMiningStatus.objects.create(
        user=user,
        status=PlaceMiningStatus.Status.SUCCEEDED,
    )
    headers = auth_headers(user)

    confirm = Client().post(f"/api/mobility/places/{place.id}/confirm", **headers)
    assert confirm.status_code == 200
    assert confirm.json()["state"] == "CONFIRMED"

    reject = Client().post(f"/api/mobility/places/{place.id}/reject", **headers)
    assert reject.json()["state"] == "REJECTED"

    reactivate = Client().post(f"/api/mobility/places/{place.id}/reactivate", **headers)
    assert reactivate.json()["state"] == "CANDIDATE"

    label = Client().post(
        f"/api/mobility/places/{place.id}/label",
        data=json.dumps({"category": "universita", "custom_name": "Bicocca"}),
        content_type="application/json",
        **headers,
    )
    assert label.status_code == 200
    body = label.json()
    assert body["category"] == "universita"
    assert body["custom_name"] == "Bicocca"
    assert body["label"] == "Bicocca"  # il nome manuale ha priorita'

    place.refresh_from_db()
    assert place.manually_reviewed is True
    assert place.category == "universita"


@pytest.mark.django_db
def test_place_actions_are_blocked_when_place_mining_is_not_ready(user):
    place = HabitualPlace.objects.create(
        user=user, center=Point(9.19, 45.46, srid=4326)
    )
    PlaceMiningStatus.objects.create(
        user=user,
        status=PlaceMiningStatus.Status.PENDING,
    )
    headers = auth_headers(user)

    endpoints = [
        (f"/api/mobility/places/{place.id}/confirm", None, None),
        (f"/api/mobility/places/{place.id}/reject", None, None),
        (f"/api/mobility/places/{place.id}/reactivate", None, None),
        (
            f"/api/mobility/places/{place.id}/label",
            json.dumps({"category": "universita", "custom_name": "Bicocca"}),
            "application/json",
        ),
    ]

    client = Client()
    for path, data, content_type in endpoints:
        kwargs = {"data": data, **headers}
        if content_type is not None:
            kwargs["content_type"] = content_type
        response = client.post(path, **kwargs)
        assert response.status_code == 409
        assert response.json() == {
            "detail": "analisi dei luoghi abituali non completata",
            "code": "place_mining_not_ready",
            "status": PlaceMiningStatus.Status.PENDING,
        }


@pytest.mark.django_db
def test_place_actions_are_blocked_without_status_record(user):
    place = HabitualPlace.objects.create(
        user=user, center=Point(9.19, 45.46, srid=4326)
    )

    response = Client().post(
        f"/api/mobility/places/{place.id}/confirm",
        **auth_headers(user),
    )

    assert response.status_code == 409
    assert response.json() == {
        "detail": "analisi dei luoghi abituali non completata",
        "code": "place_mining_not_ready",
        "status": PlaceMiningStatus.Status.IDLE,
    }


@pytest.mark.django_db
def test_place_label_rejects_invalid_category(user):
    place = HabitualPlace.objects.create(
        user=user, center=Point(9.19, 45.46, srid=4326)
    )
    response = Client().post(
        f"/api/mobility/places/{place.id}/label",
        data=json.dumps({"category": "aeroporto"}),
        content_type="application/json",
        **auth_headers(user),
    )
    assert response.status_code == 422


@pytest.mark.django_db
def test_place_actions_are_user_scoped(user, other_user):
    place = HabitualPlace.objects.create(
        user=user, center=Point(9.19, 45.46, srid=4326)
    )
    response = Client().post(
        f"/api/mobility/places/{place.id}/confirm", **auth_headers(other_user)
    )
    assert response.status_code == 404


def _read_streaming_body(response) -> str:
    """Consuma il body async di una StreamingHttpResponse da un test sincrono."""

    async def _collect():
        parts = []
        async for part in response.streaming_content:
            parts.append(part)
        return b"".join(parts)

    return async_to_sync(_collect)().decode("utf-8")


class _FakePubSub:
    def __init__(self, messages=None):
        self.messages = list(messages or [])
        self.subscribed = []
        self.unsubscribed = []
        self.listen_called = False
        self.closed = False

    async def subscribe(self, channel):
        self.subscribed.append(channel)

    async def unsubscribe(self, channel):
        self.unsubscribed.append(channel)

    async def aclose(self):
        self.closed = True

    async def listen(self):
        self.listen_called = True
        yield {"type": "subscribe"}
        for data in self.messages:
            yield {"type": "message", "data": data}
        while True:
            await asyncio.sleep(3600)


class _FakeRedis:
    def __init__(self, pubsub):
        self._pubsub = pubsub
        self.closed = False

    def pubsub(self):
        return self._pubsub

    async def aclose(self):
        self.closed = True


def _install_fake_diary_redis(monkeypatch, *, messages=None):
    pubsub = _FakePubSub(messages)
    client = _FakeRedis(pubsub)
    monkeypatch.setattr(mobility_api, "create_async_redis_client", lambda: client)
    return pubsub, client


@pytest.mark.django_db
def test_trip_events_emits_enriched_diary_status_for_processed_trip(
    user,
    monkeypatch,
):
    trip = create_trip(user)
    trip.status = Trip.Status.PROCESSED
    trip.save(update_fields=["status", "updated_at"])
    _install_fake_diary_redis(monkeypatch)

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/events",
        **auth_headers(user),
    )

    assert response.status_code == 200
    assert response["Content-Type"].startswith("text/event-stream")
    body = _read_streaming_body(response)
    assert "event: diary_status" in body
    assert f'"trip_id":{trip.id}' in body
    assert '"status":"enriched"' in body


@pytest.mark.django_db
def test_trip_events_emits_failed_diary_status_for_final_ingestion_failure(
    user,
    monkeypatch,
):
    trip = create_trip(user)
    TripIngestion.objects.create(
        user=user,
        trip=trip,
        client_session_id="failed-raw",
        raw_status=TripIngestion.PhaseStatus.FAILED_FINAL,
    )
    _install_fake_diary_redis(monkeypatch)

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/events",
        **auth_headers(user),
    )

    assert response.status_code == 200
    body = _read_streaming_body(response)
    assert "event: diary_status" in body
    assert f'"trip_id":{trip.id}' in body
    assert '"status":"failed"' in body
    assert '"reason":"diary_enrichment_failed"' in body


@pytest.mark.django_db
def test_trip_events_returns_404_for_other_user(user, other_user):
    trip = create_trip(user)

    response = Client().get(
        f"/api/mobility/trips/{trip.id}/events",
        **auth_headers(other_user),
    )

    assert response.status_code == 404


@pytest.mark.django_db
def test_trip_diary_failure_reason_ignores_retryable_ingestion(user):
    trip = create_trip(user)
    TripIngestion.objects.create(
        user=user,
        trip=trip,
        client_session_id="retryable-raw",
        raw_status=TripIngestion.PhaseStatus.FAILED_RETRYABLE,
    )

    reason = async_to_sync(mobility_api._trip_diary_failure_reason)(
        trip.id,
        user.id,
    )

    assert reason is None


def test_trip_event_stream_emits_current_status_after_subscribe(monkeypatch):
    pubsub, _client = _install_fake_diary_redis(monkeypatch)

    async def fake_current_status(trip_id, user_id):
        assert pubsub.subscribed == ["diary_status:7"]
        return {"trip_id": trip_id, "status": "enriched"}

    monkeypatch.setattr(
        mobility_api,
        "_trip_diary_status_payload",
        fake_current_status,
    )

    async def collect():
        stream = mobility_api._trip_diary_event_stream(
            7,
            11,
            max_seconds=10,
        )
        return [chunk async for chunk in stream]

    results = async_to_sync(collect)()

    assert results == [
        'event: diary_status\ndata: {"trip_id":7,"status":"enriched"}\n\n',
    ]
    assert pubsub.listen_called is False
    assert pubsub.unsubscribed == ["diary_status:7"]


def test_trip_event_stream_emits_published_diary_status(monkeypatch):
    _install_fake_diary_redis(
        monkeypatch,
        messages=[
            (
                '{"trip_id":7,"status":"failed",'
                '"reason":"diary_enrichment_failed"}'
            ),
        ],
    )

    async def fake_current_status(trip_id, user_id):
        return None

    monkeypatch.setattr(
        mobility_api,
        "_trip_diary_status_payload",
        fake_current_status,
    )

    async def collect():
        stream = mobility_api._trip_diary_event_stream(
            7,
            11,
            max_seconds=10,
        )
        return [chunk async for chunk in stream]

    results = async_to_sync(collect)()

    assert results == [
        (
            'event: diary_status\n'
            'data: {"trip_id":7,"status":"failed",'
            '"reason":"diary_enrichment_failed"}\n\n'
        ),
    ]


def test_trip_event_stream_times_out_without_diary_status(monkeypatch):
    _install_fake_diary_redis(monkeypatch)

    async def fake_current_status(trip_id, user_id):
        return None

    monkeypatch.setattr(
        mobility_api,
        "_trip_diary_status_payload",
        fake_current_status,
    )

    async def collect():
        stream = mobility_api._trip_diary_event_stream(
            7,
            11,
            max_seconds=0.01,
        )
        return [chunk async for chunk in stream]

    results = async_to_sync(collect)()

    assert results == [": timeout\n\n"]
