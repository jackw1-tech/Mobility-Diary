import math
from dataclasses import dataclass

from django.contrib.gis.geos import LineString, Point

from .geo import haversine_meters


WEB_MERCATOR_RADIUS_METERS = 6378137.0
WEB_MERCATOR_MAX_LATITUDE = 85.05112878

# Generic wording for stops/places once a non-precise level masks the real
# semantic label (home, work, ...). Shared by the web dashboard and the mobile
# text export so both speak about a region, not a recognizable place.
PRIVACY_AWARE_STOP_LABEL = "Sosta significativa in area approssimata"


@dataclass(frozen=True)
class CloakedLine:
    coordinates: list[tuple[float, float]]
    point_count: int
    distance_meters: float


@dataclass(frozen=True)
class PrivacyMetrics:
    """Privacy/quality trade-off summary for one cloaked trajectory.

    Perturbation is the distance between each real point and its published
    cell center, computed over every original point before any display-only
    duplicate collapse. Quality of service is the relative route-distance error
    between the private and privacy-aware trajectories.
    """

    perturbation_mean_meters: float
    perturbation_max_meters: float
    perturbation_sample_count: int
    private_distance_meters: float
    privacy_aware_distance_meters: float
    relative_distance_error: float


def privacy_cell_size_meters(level: str) -> int | None:
    if level == "approximate":
        return 150
    if level == "aggregated":
        return 400
    return None


def cloak_linestring(
    geometry: LineString | None,
    *,
    level: str,
) -> CloakedLine | None:
    if geometry is None:
        return None

    coordinates = [(float(lon), float(lat)) for lon, lat, *_ in geometry.coords]
    cell_size_meters = privacy_cell_size_meters(level)
    if cell_size_meters is not None:
        coordinates = _collapse_consecutive_duplicates(
            [
                _cloak_coordinate(lon, lat, cell_size_meters=cell_size_meters)
                for lon, lat in coordinates
            ]
        )

    return CloakedLine(
        coordinates=coordinates,
        point_count=len(coordinates),
        distance_meters=_line_distance_meters(coordinates),
    )


def line_geojson(cloaked_line: CloakedLine | None) -> dict | None:
    if cloaked_line is None:
        return None
    return {
        "type": "LineString",
        "coordinates": [
            [round(lon, 7), round(lat, 7)] for lon, lat in cloaked_line.coordinates
        ],
    }


def cloak_point(
    point: Point | None,
    *,
    level: str,
) -> tuple[float, float] | None:
    """Cloak a single position using the same metric grid as the tracks.

    Significant places reuse the track cloaking so a home/work center collapses
    to the same cell center the trajectory would.
    """
    if point is None:
        return None

    cell_size_meters = privacy_cell_size_meters(level)
    if cell_size_meters is None:
        return (float(point.x), float(point.y))
    return _cloak_coordinate(
        float(point.x),
        float(point.y),
        cell_size_meters=cell_size_meters,
    )


def point_geojson(coordinate: tuple[float, float] | None) -> dict | None:
    if coordinate is None:
        return None
    lon, lat = coordinate
    return {"type": "Point", "coordinates": [round(lon, 7), round(lat, 7)]}


def privacy_metrics(
    geometry: LineString | None,
    *,
    level: str,
) -> PrivacyMetrics:
    if geometry is None:
        return PrivacyMetrics(0.0, 0.0, 0, 0.0, 0.0, 0.0)

    originals = [(float(lon), float(lat)) for lon, lat, *_ in geometry.coords]
    cell_size_meters = privacy_cell_size_meters(level)
    # `precise` publishes the real points, so cloaked == originals and every
    # metric below collapses to zero loss without a separate branch.
    cloaked = originals if cell_size_meters is None else [
        _cloak_coordinate(lon, lat, cell_size_meters=cell_size_meters)
        for lon, lat in originals
    ]
    # Perturbation pairs every original point with its published cell center,
    # before collapsing consecutive duplicate cells for display.
    perturbations = [
        haversine_meters(original[1], original[0], published[1], published[0])
        for original, published in zip(originals, cloaked)
    ]
    private_distance = _line_distance_meters(originals)
    privacy_distance = _line_distance_meters(_collapse_consecutive_duplicates(cloaked))
    return PrivacyMetrics(
        perturbation_mean_meters=sum(perturbations) / len(perturbations)
        if perturbations
        else 0.0,
        perturbation_max_meters=max(perturbations, default=0.0),
        perturbation_sample_count=len(perturbations),
        private_distance_meters=private_distance,
        privacy_aware_distance_meters=privacy_distance,
        relative_distance_error=abs(private_distance - privacy_distance)
        / private_distance
        if private_distance > 0
        else 0.0,
    )


def _cloak_coordinate(
    lon: float,
    lat: float,
    *,
    cell_size_meters: int,
) -> tuple[float, float]:
    x, y = _lon_lat_to_web_mercator(lon, lat)
    cloaked_x = math.floor(x / cell_size_meters) * cell_size_meters
    cloaked_y = math.floor(y / cell_size_meters) * cell_size_meters
    return _web_mercator_to_lon_lat(
        cloaked_x + cell_size_meters / 2,
        cloaked_y + cell_size_meters / 2,
    )


def _lon_lat_to_web_mercator(lon: float, lat: float) -> tuple[float, float]:
    clamped_lat = max(
        -WEB_MERCATOR_MAX_LATITUDE,
        min(WEB_MERCATOR_MAX_LATITUDE, lat),
    )
    lon_rad = math.radians(lon)
    lat_rad = math.radians(clamped_lat)
    x = WEB_MERCATOR_RADIUS_METERS * lon_rad
    y = WEB_MERCATOR_RADIUS_METERS * math.log(math.tan(math.pi / 4 + lat_rad / 2))
    return x, y


def _web_mercator_to_lon_lat(x: float, y: float) -> tuple[float, float]:
    lon = math.degrees(x / WEB_MERCATOR_RADIUS_METERS)
    lat = math.degrees(
        2 * math.atan(math.exp(y / WEB_MERCATOR_RADIUS_METERS)) - math.pi / 2
    )
    return lon, lat


def _collapse_consecutive_duplicates(
    coordinates: list[tuple[float, float]],
) -> list[tuple[float, float]]:
    collapsed: list[tuple[float, float]] = []
    for coordinate in coordinates:
        if not collapsed or coordinate != collapsed[-1]:
            collapsed.append(coordinate)

    if len(collapsed) == 1 and len(coordinates) > 1:
        return [collapsed[0], collapsed[0]]
    return collapsed


def _line_distance_meters(coordinates: list[tuple[float, float]]) -> float:
    return sum(
        haversine_meters(start[1], start[0], end[1], end[0])
        for start, end in zip(coordinates, coordinates[1:])
    )
