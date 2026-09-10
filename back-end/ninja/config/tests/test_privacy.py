from datetime import datetime, timedelta, timezone

import pytest
from django.contrib.gis.geos import LineString

from mobility.diary_export import (
    DiaryExportSegment,
    _aggregated_text,
    _ceil_time,
    _floor_time,
)
from mobility.models import MobilitySegment
from mobility.privacy import approximate_linestring, privacy_metrics


@pytest.mark.django_db
def test_approximate_linestring_returns_a_geos_linestring() -> None:
    original = LineString((9.0, 45.0), (9.00001, 45.00001), srid=4326)

    result = approximate_linestring(original, level="approximate")

    assert result is not None
    assert isinstance(result.geometry, LineString)
    assert result.geometry.srid == 4326
    assert result.geometry.num_coords == 2
    assert result.geometry[0] == result.geometry[1]
    assert result.distance_meters == 0.0


@pytest.mark.django_db
def test_privacy_metrics_calculates_both_lengths_in_one_query(
    django_assert_num_queries,
) -> None:
    original = LineString((9.0, 45.0), (9.01, 45.01), srid=4326)

    with django_assert_num_queries(1):
        metrics = privacy_metrics(original, level="approximate")

    assert metrics.private_distance_meters > 0
    assert metrics.privacy_aware_distance_meters > 0


def test_time_rounding_preserves_microseconds_until_rounding() -> None:
    value = datetime(2026, 9, 10, 10, 5, 0, 500_000, tzinfo=timezone.utc)
    step = timedelta(minutes=5)

    assert _floor_time(value, step) == datetime(
        2026, 9, 10, 10, 5, tzinfo=timezone.utc
    )
    assert _ceil_time(value, step) == datetime(
        2026, 9, 10, 10, 10, tzinfo=timezone.utc
    )


def test_aggregated_text_groups_readable_details_by_day_period() -> None:
    def segment(
        kind: str,
        start_label: str,
        end_label: str,
        duration: timedelta,
        *,
        distance_meters: float = 0.0,
        activity_label: str = "IDLE",
    ) -> DiaryExportSegment:
        start = datetime(2026, 9, 10, tzinfo=timezone.utc)
        return DiaryExportSegment(
            kind=kind,
            start_timestamp=start,
            end_timestamp=start + duration,
            start_label=start_label,
            end_label=end_label,
            activity_label=activity_label,
            title="",
            point_count=0,
            coordinates=[],
            duration=duration,
            distance_meters=distance_meters,
        )

    morning_move = segment(
        MobilitySegment.Kind.MOVE,
        "06:00",
        "12:00",
        timedelta(minutes=30),
        distance_meters=2500,
        activity_label="WALKING",
    )
    morning_stop = segment(
        MobilitySegment.Kind.STOP,
        "06:00",
        "12:00",
        timedelta(hours=5, minutes=15),
    )
    afternoon_move = segment(
        MobilitySegment.Kind.MOVE,
        "12:00",
        "18:00",
        timedelta(minutes=30),
        distance_meters=700,
        activity_label="WALKING",
    )
    afternoon_stop = segment(
        MobilitySegment.Kind.STOP,
        "12:00",
        "18:00",
        timedelta(hours=1, minutes=5),
    )

    text = _aggregated_text(
        trip_id=11,
        cell_size_meters=400,
        segments=[morning_stop, afternoon_stop, afternoon_stop],
        aggregated_segments=[
            morning_move,
            morning_stop,
            afternoon_move,
            afternoon_stop,
        ],
    )

    assert text == """DIARIO AGGREGATO
Viaggio #11

PRIVACY
Le informazioni geografiche sono rappresentate in aree da 400 m.
Percorsi precisi e luoghi esatti non sono inclusi.

MATTINA · 06:00–12:00

- Movimento: 30 min
- Modalità: A piedi
- Distanza: 1–3 km
- Tempo in sosta: 5 h 15 min

POMERIGGIO · 12:00–18:00

- Movimento: 30 min
- Modalità: A piedi
- Distanza: Meno di 1 km
- Tempo in sosta: 1 h 5 min

TOTALE DELLA GIORNATA

- Movimento: 1 h
- Tempo in sosta: 6 h 20 min
- Distanza: 3–5 km
- Aree visitate: 3"""
