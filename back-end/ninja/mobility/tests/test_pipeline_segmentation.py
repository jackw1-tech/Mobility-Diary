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
                to_state="ACTIVE_TRACKING",
                reason="start",
                timestamp=base,
            ),
            StateTransition(
                trip=trip,
                from_state="ACTIVE_TRACKING",
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
