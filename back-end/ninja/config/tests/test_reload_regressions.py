from datetime import datetime, timedelta, timezone

import pytest
from django.contrib.gis.geos import LineString, Point

from mobility import api as mobility_api
from mobility.models import (
    GpsPoint,
    MobilitySegment,
    RawSensorReading,
    StateTransition,
    Trip,
    TripUpload,
    TripUploadPart,
)
from mobility.selectors.sensor_readings import replace_raw_sensor_readings_from_source
from mobility.services import reload as reload_service


pytestmark = pytest.mark.django_db(transaction=True)


def _reloadable_source(user_id: int) -> tuple[Trip, TripUploadPart]:
    started_at = datetime(2026, 9, 1, 10, tzinfo=timezone.utc)
    source = Trip.objects.create(
        user_id=user_id,
        client_session_id="reload-source",
        device_id="test-device",
        status=Trip.Status.PROCESSED,
        is_reloadable=True,
        started_at=started_at,
        ended_at=started_at + timedelta(minutes=10),
    )
    GpsPoint.objects.bulk_create(
        [
            GpsPoint(
                trip=source,
                timestamp=started_at,
                point=Point(9.19, 45.46, srid=4326),
            ),
            GpsPoint(
                trip=source,
                timestamp=started_at + timedelta(minutes=10),
                point=Point(9.20, 45.47, srid=4326),
            ),
        ]
    )
    StateTransition.objects.create(
        trip=source,
        timestamp=started_at + timedelta(minutes=4),
        from_state="STILL",
        to_state="MOVING",
    )
    upload = TripUpload.objects.create(
        user_id=user_id,
        client_session_id="reload-source-upload",
        device_id="test-device",
        core_status=TripUpload.PhaseStatus.COMPLETED,
        raw_status=TripUpload.PhaseStatus.COMPLETED,
        trip=source,
        started_at=source.started_at,
        ended_at=source.ended_at,
    )
    part = TripUploadPart.objects.create(
        upload=upload,
        sequence=1,
        sha256="a" * 64,
        object_key="uploads/source/sensor_windows_part_0001.json.gz",
        received_at=source.ended_at,
    )
    return source, part


def test_direct_reload_queues_raw_regeneration_without_reading_the_object(
    mobile_session,
    monkeypatch,
):
    source, _ = _reloadable_source(mobile_session["user"]["id"])
    reads = []
    queued = []
    monkeypatch.setattr(
        reload_service.storage,
        "head_object",
        lambda _key: {"ContentLength": 123},
    )
    monkeypatch.setattr(
        reload_service.storage,
        "read_object",
        lambda key: reads.append(key),
        raising=False,
    )
    monkeypatch.setattr(
        reload_service.prepare_reloaded_trip_raw,
        "delay",
        lambda upload_id, source_trip_id, shift_us: queued.append(
            (upload_id, source_trip_id, shift_us)
        ),
    )

    result = reload_service.reload_trip_from_source(
        user_id=mobile_session["user"]["id"],
        trip_id=source.id,
        reload_request_id="request-1",
        scheduled_start_at=datetime(2026, 8, 30, 10, tzinfo=timezone.utc),
        now=datetime(2026, 9, 3, 10, tzinfo=timezone.utc),
    )

    assert result["core_status"] == TripUpload.PhaseStatus.COMPLETED
    assert result["raw_status"] == TripUpload.PhaseStatus.PENDING
    assert result["map_available"] is True
    assert Trip.objects.get(id=result["trip_id"]).client_session_id == "reload-request-1"
    assert reads == []
    assert queued == [(result["upload_id"], source.id, -172800000000)]


def test_direct_reload_rejects_missing_raw_before_creating_the_derived_trip(
    mobile_session,
    monkeypatch,
):
    source, _ = _reloadable_source(mobile_session["user"]["id"])
    monkeypatch.setattr(reload_service.storage, "head_object", lambda _key: None)
    before = Trip.objects.count()

    with pytest.raises(reload_service.ReloadServiceError):
        reload_service.reload_trip_from_source(
            user_id=mobile_session["user"]["id"],
            trip_id=source.id,
            reload_request_id="request-2",
            scheduled_start_at=datetime(2026, 8, 30, 10, tzinfo=timezone.utc),
            now=datetime(2026, 9, 3, 10, tzinfo=timezone.utc),
        )

    assert Trip.objects.count() == before
    assert not Trip.objects.filter(reloaded_from_trip=source).exists()


def test_derived_raw_readings_are_cloned_inside_postgres():
    source = Trip.objects.create(device_id="source")
    derived = Trip.objects.create(device_id="derived", reloaded_from_trip=source)
    start = datetime(2026, 9, 1, 10, tzinfo=timezone.utc)
    RawSensorReading.objects.bulk_create(
        [
            RawSensorReading(
                trip=source,
                timestamp=start + timedelta(milliseconds=index * 10),
                accel_x=1 + index,
                accel_y=2,
                accel_z=3,
                gyro_x=4,
                gyro_y=5,
                gyro_z=6,
            )
            for index in range(2)
        ]
    )

    count = replace_raw_sensor_readings_from_source(
        derived,
        source,
        shift=timedelta(hours=2),
    )

    rows = list(
        RawSensorReading.objects.filter(trip=derived)
        .order_by("timestamp")
        .values_list("timestamp", "accel_x")
    )
    assert count == 2
    assert rows == [
        (start + timedelta(hours=2), 1.0),
        (start + timedelta(hours=2, milliseconds=10), 2.0),
    ]


def test_pending_diary_does_not_poison_the_processed_diary_cache(
    api_client,
    mobile_session,
    monkeypatch,
):
    trip = Trip.objects.create(
        user_id=mobile_session["user"]["id"],
        device_id="test-device",
        status=Trip.Status.CLOSED,
        started_at=datetime(2026, 9, 1, 10, tzinfo=timezone.utc),
        ended_at=datetime(2026, 9, 1, 10, 10, tzinfo=timezone.utc),
    )
    cached = {}
    monkeypatch.setattr(mobility_api, "get_places_version", lambda _user_id: 0)
    monkeypatch.setattr(
        mobility_api,
        "get_cached_diary",
        lambda trip_id, version: cached.get((trip_id, version)),
    )
    monkeypatch.setattr(
        mobility_api,
        "cache_diary",
        lambda trip_id, version, diary: cached.__setitem__(
            (trip_id, version), diary
        ),
    )

    pending = api_client.get(
        f"/api/mobility/trips/{trip.id}/diary",
        HTTP_AUTHORIZATION=mobile_session["headers"]["HTTP_AUTHORIZATION"],
    )
    assert pending.json()["processed"] is False
    assert cached == {}

    MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.MOVE,
        start_timestamp=trip.started_at,
        end_timestamp=trip.ended_at,
        activity_label="WALKING",
        distance_meters=100,
        path=LineString((9.19, 45.46), (9.20, 45.47), srid=4326),
    )
    trip.status = Trip.Status.PROCESSED
    trip.save(update_fields=["status", "updated_at"])

    processed = api_client.get(
        f"/api/mobility/trips/{trip.id}/diary",
        HTTP_AUTHORIZATION=mobile_session["headers"]["HTTP_AUTHORIZATION"],
    )
    assert processed.json()["processed"] is True
    assert len(processed.json()["segments"]) == 1


def test_direct_reload_copies_core_evidence_shifted(mobile_session, monkeypatch):
    """La copia core deve portare punti GPS *e* transizioni di stato.

    Senza transizioni la pipeline HAR ricostruisce macro-span sbagliati e il
    derivato esce con un diario diverso dal sorgente pur avendo la mappa.
    """
    source, _ = _reloadable_source(mobile_session["user"]["id"])
    monkeypatch.setattr(
        reload_service.storage,
        "head_object",
        lambda _key: {"ContentLength": 123},
    )
    monkeypatch.setattr(
        reload_service.prepare_reloaded_trip_raw,
        "delay",
        lambda *args, **kwargs: None,
    )

    result = reload_service.reload_trip_from_source(
        user_id=mobile_session["user"]["id"],
        trip_id=source.id,
        reload_request_id="request-3",
        scheduled_start_at=datetime(2026, 8, 30, 10, tzinfo=timezone.utc),
        now=datetime(2026, 9, 3, 10, tzinfo=timezone.utc),
    )

    derived = Trip.objects.get(id=result["trip_id"])
    shift = timedelta(days=-2)
    assert result["state_transitions"] == 1
    assert list(
        derived.state_transitions.order_by("timestamp").values_list(
            "timestamp", "to_state"
        )
    ) == [(source.started_at + timedelta(minutes=4) + shift, "MOVING")]
    assert list(
        derived.gps_points.order_by("timestamp").values_list("timestamp", flat=True)
    ) == [
        source.started_at + shift,
        source.started_at + timedelta(minutes=10) + shift,
    ]
