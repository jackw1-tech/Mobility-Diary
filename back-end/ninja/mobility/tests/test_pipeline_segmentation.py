from datetime import timedelta

import pytest
from django.contrib.auth import get_user_model
from django.contrib.gis.geos import Point
from django.utils import timezone

from mobility.ml.classifier import ClassifierResult
from mobility.ml.pipeline import PipelineSensorWindow, run_pipeline
from mobility.models import (
    ActivityLabel,
    GpsPoint,
    MobilitySegment,
    StateTransition,
    Trip,
    VirtualStopInterval,
)


@pytest.fixture
def user(db):
    return get_user_model().objects.create_user(
        username="pipeline-owner@example.com",
        email="pipeline-owner@example.com",
        password="password",
    )


def _window(start, seconds: int):
    return PipelineSensorWindow(
        start_timestamp=start,
        end_timestamp=start + timedelta(seconds=seconds),
        sample_count=500,
        frequency_hz=100,
        matrix=[[0.0] * 9 for _ in range(500)],
    )


@pytest.mark.django_db
def test_pipeline_smooths_isolated_short_har_label_changes(user, monkeypatch):
    base = timezone.now()
    trip = Trip.objects.create(
        user=user,
        client_session_id="smooth-isolated-label",
        device_id="test-device",
        status=Trip.Status.CLOSED,
        ended_at=base + timedelta(seconds=90),
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
                timestamp=base + timedelta(seconds=90),
            ),
        ]
    )
    for offset, lon, lat in [
        (0, 9.10, 45.46),
        (30, 9.11, 45.47),
        (60, 9.12, 45.48),
        (89, 9.13, 45.49),
    ]:
        GpsPoint.objects.create(
            trip=trip,
            timestamp=base + timedelta(seconds=offset),
            point=Point(lon, lat, srid=4326),
            speed_mps=4.0,
        )
    windows = [
        _window(base, 30),
        _window(base + timedelta(seconds=30), 15),
        _window(base + timedelta(seconds=45), 45),
    ]

    def fake_classify(_normalized, _speeds, *, raw_windows=None):
        return ClassifierResult(
            labels=[
                ActivityLabel.BIKING,
                ActivityLabel.WALKING,
                ActivityLabel.BIKING,
            ],
            summary={"classifier": "fake"},
        )

    monkeypatch.setattr("mobility.ml.pipeline.classify_windows", fake_classify)

    result = run_pipeline(trip, sensor_windows=windows)

    assert result["segments"] == 1
    segment = MobilitySegment.objects.get(trip=trip)
    assert segment.kind == MobilitySegment.Kind.MOVE
    assert segment.activity_label == ActivityLabel.BIKING
    assert segment.start_timestamp == base
    assert segment.end_timestamp == base + timedelta(seconds=90)
    assert segment.path is not None
    assert VirtualStopInterval.objects.filter(trip=trip).count() == 0


@pytest.mark.django_db
def test_pipeline_absorbs_short_idle_into_previous_activity(user, monkeypatch):
    base = timezone.now()
    trip = Trip.objects.create(
        user=user,
        client_session_id="short-idle-previous",
        device_id="test-device",
        status=Trip.Status.CLOSED,
        ended_at=base + timedelta(seconds=150),
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
                timestamp=base + timedelta(seconds=150),
            ),
        ]
    )
    for offset, lon, lat in [
        (0, 9.10, 45.46),
        (60, 9.11, 45.47),
        (120, 9.12, 45.48),
        (149, 9.13, 45.49),
    ]:
        GpsPoint.objects.create(
            trip=trip,
            timestamp=base + timedelta(seconds=offset),
            point=Point(lon, lat, srid=4326),
            speed_mps=2.0,
        )
    windows = [
        _window(base, 30),
        _window(base + timedelta(seconds=30), 90),
        _window(base + timedelta(seconds=120), 30),
    ]

    monkeypatch.setattr(
        "mobility.ml.pipeline.classify_windows",
        lambda *_args, **_kwargs: ClassifierResult(
            labels=[
                ActivityLabel.BIKING,
                ActivityLabel.IDLE,
                ActivityLabel.WALKING,
            ],
            summary={"classifier": "fake"},
        ),
    )
    monkeypatch.setattr(
        "mobility.ml.pipeline.correct_idle_with_gps",
        lambda labels, _speeds: labels,
    )

    result = run_pipeline(trip, sensor_windows=windows)

    segments = list(trip.segments.order_by("start_timestamp"))
    assert result["segments"] == 2
    assert result["virtual_stop_intervals"] == 0
    assert [segment.activity_label for segment in segments] == [
        ActivityLabel.BIKING,
        ActivityLabel.WALKING,
    ]
    assert segments[0].start_timestamp == base
    assert segments[0].end_timestamp == base + timedelta(seconds=120)
    assert segments[1].start_timestamp == base + timedelta(seconds=120)
    assert segments[1].end_timestamp == base + timedelta(seconds=150)


@pytest.mark.django_db
def test_pipeline_absorbs_initial_short_idle_into_next_activity(user, monkeypatch):
    base = timezone.now()
    trip = Trip.objects.create(
        user=user,
        client_session_id="short-idle-next",
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
    windows = [
        _window(base, 90),
        _window(base + timedelta(seconds=90), 30),
    ]

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

    result = run_pipeline(trip, sensor_windows=windows)

    segments = list(trip.segments.order_by("start_timestamp"))
    assert result["segments"] == 1
    assert result["virtual_stop_intervals"] == 0
    assert segments[0].activity_label == ActivityLabel.WALKING
    assert segments[0].start_timestamp == base
    assert segments[0].end_timestamp == base + timedelta(seconds=120)


@pytest.mark.django_db
def test_pipeline_materializes_long_idle_run_as_virtual_stop(user, monkeypatch):
    base = timezone.now()
    trip = Trip.objects.create(
        user=user,
        client_session_id="long-idle-virtual-stop",
        device_id="test-device",
        status=Trip.Status.CLOSED,
        ended_at=base + timedelta(minutes=9),
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
                timestamp=base + timedelta(minutes=9),
            ),
        ]
    )
    for offset, lon, lat, speed in [
        (0, 9.10, 45.46, 2.0),
        (180, 9.11, 45.47, 0.0),
        (360, 9.12, 45.48, 2.0),
        (539, 9.13, 45.49, 2.0),
    ]:
        GpsPoint.objects.create(
            trip=trip,
            timestamp=base + timedelta(seconds=offset),
            point=Point(lon, lat, srid=4326),
            speed_mps=speed,
        )
    windows = [
        _window(base, 180),
        _window(base + timedelta(seconds=180), 180),
        _window(base + timedelta(seconds=360), 180),
    ]

    monkeypatch.setattr(
        "mobility.ml.pipeline.classify_windows",
        lambda *_args, **_kwargs: ClassifierResult(
            labels=[
                ActivityLabel.BIKING,
                ActivityLabel.IDLE,
                ActivityLabel.WALKING,
            ],
            summary={"classifier": "fake"},
        ),
    )
    monkeypatch.setattr(
        "mobility.ml.pipeline.correct_idle_with_gps",
        lambda labels, _speeds: labels,
    )

    result = run_pipeline(trip, sensor_windows=windows)

    segments = list(trip.segments.order_by("start_timestamp"))
    virtual_stop = VirtualStopInterval.objects.get(trip=trip)
    assert result["segments"] == 2
    assert result["virtual_stop_intervals"] == 1
    assert [segment.activity_label for segment in segments] == [
        ActivityLabel.BIKING,
        ActivityLabel.WALKING,
    ]
    assert virtual_stop.start_timestamp == base + timedelta(seconds=180)
    assert virtual_stop.end_timestamp == base + timedelta(seconds=360)


@pytest.mark.django_db
def test_pipeline_keeps_existing_diary_if_rebuild_fails(user, monkeypatch):
    base = timezone.now()
    trip = Trip.objects.create(
        user=user,
        client_session_id="pipeline-atomic-rebuild",
        device_id="test-device",
        status=Trip.Status.CLOSED,
        ended_at=base + timedelta(minutes=5),
    )
    previous_segment = MobilitySegment.objects.create(
        trip=trip,
        kind=MobilitySegment.Kind.MOVE,
        start_timestamp=base,
        end_timestamp=base + timedelta(minutes=2),
        activity_label=ActivityLabel.WALKING,
        distance_meters=120,
    )
    previous_virtual_stop = VirtualStopInterval.objects.create(
        trip=trip,
        start_timestamp=base + timedelta(minutes=2),
        end_timestamp=base + timedelta(minutes=3),
    )

    monkeypatch.setattr(
        "mobility.ml.pipeline.classify_windows",
        lambda *_args, **_kwargs: ClassifierResult(
            labels=[],
            summary={"classifier": "fake"},
        ),
    )
    monkeypatch.setattr(
        "mobility.ml.pipeline._macro_spans",
        lambda *_args, **_kwargs: [
            (
                base,
                base + timedelta(minutes=5),
                MobilitySegment.Kind.MOVE,
            )
        ],
    )
    monkeypatch.setattr(
        "mobility.ml.pipeline._build_move",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(RuntimeError("boom")),
    )

    with pytest.raises(RuntimeError, match="boom"):
        run_pipeline(trip, sensor_windows=[])

    assert MobilitySegment.objects.filter(pk=previous_segment.pk).exists()
    assert VirtualStopInterval.objects.filter(pk=previous_virtual_stop.pk).exists()
    trip.refresh_from_db()
    assert trip.status == Trip.Status.CLOSED
