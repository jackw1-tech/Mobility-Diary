import pytest
from django.contrib.gis.geos import LineString, Point

from mobility.privacy import (
    cloak_linestring,
    cloak_point,
    line_geojson,
    point_geojson,
    privacy_metrics,
)


def test_metric_grid_cloaking_is_deterministic():
    line = LineString((9.123456, 45.456789), (9.124456, 45.457789), srid=4326)

    first = line_geojson(cloak_linestring(line, level="approximate"))
    second = line_geojson(cloak_linestring(line, level="approximate"))

    assert first == second


def test_metric_grid_cloaking_is_not_decimal_truncation():
    line = LineString((9.123456, 45.456789), (9.124456, 45.457789), srid=4326)

    cloaked = line_geojson(cloak_linestring(line, level="approximate"))

    assert cloaked["coordinates"][0] != [9.123456, 45.456789]
    assert cloaked["coordinates"][0] != [9.123, 45.456]
    assert -180 <= cloaked["coordinates"][0][0] <= 180
    assert -90 <= cloaked["coordinates"][0][1] <= 90


def test_cloak_point_reuses_track_grid_and_is_deterministic():
    point = Point(9.123456, 45.456789, srid=4326)
    line = LineString((9.123456, 45.456789), (9.123466, 45.456799), srid=4326)

    cloaked_point = cloak_point(point, level="approximate")
    cloaked_line = cloak_linestring(line, level="approximate")

    assert cloaked_point == pytest.approx(cloaked_line.coordinates[0])
    assert cloak_point(point, level="approximate") == cloaked_point


def test_cloak_point_precise_is_identity():
    point = Point(9.123456, 45.456789, srid=4326)

    assert cloak_point(point, level="precise") == (9.123456, 45.456789)
    assert point_geojson(cloak_point(point, level="precise")) == {
        "type": "Point",
        "coordinates": [9.123456, 45.456789],
    }


def test_privacy_metrics_precise_has_zero_perturbation_and_loss():
    line = LineString((9.10, 45.46), (9.20, 45.47), srid=4326)

    metrics = privacy_metrics(line, level="precise")

    assert metrics.perturbation_mean_meters == 0.0
    assert metrics.perturbation_max_meters == 0.0
    assert metrics.relative_distance_error == 0.0
    assert metrics.private_distance_meters == pytest.approx(
        metrics.privacy_aware_distance_meters
    )


def test_privacy_metrics_grow_with_cell_size():
    line = LineString((9.10, 45.46), (9.11, 45.461), (9.12, 45.462), srid=4326)

    approximate = privacy_metrics(line, level="approximate")
    aggregated = privacy_metrics(line, level="aggregated")

    # Perturbation is computed over every original point, before display collapse.
    assert approximate.perturbation_sample_count == 3
    assert approximate.perturbation_max_meters > 0
    assert aggregated.perturbation_mean_meters > approximate.perturbation_mean_meters
    assert aggregated.perturbation_max_meters <= 400 * (2 ** 0.5)
