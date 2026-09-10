import math
from dataclasses import dataclass

from django.contrib.gis.geos import LineString, Point
from django.db import connection

from .geo import haversine_meters



PRIVACY_AWARE_STOP_LABEL = "Sosta in area approssimata"


@dataclass(frozen=True)
class ApproximatedLine:
    geometry: LineString
    distance_meters: float


@dataclass(frozen=True)
class PrivacyMetrics:
    perturbation_mean_meters: float
    perturbation_max_meters: float
    perturbation_sample_count: int
    private_distance_meters: float
    privacy_aware_distance_meters: float
    relative_distance_error: float


# Dimensione della griglia di approssimazione per ogni livello privacy.
def privacy_cell_size_meters(level: str) -> int | None:
    if level == "approximate":
        return 150
    if level == "aggregated":
        return 400
    return None

# Ricrea una LineString approssimando i suoi punti GPS.
def approximate_linestring(
    geometry: LineString | None,
    *,
    level: str,
) -> ApproximatedLine | None:
    if geometry is None:
        return None

    coordinates = [(float(lon), float(lat)) for lon, lat, *_ in geometry.coords]
    cell_size_meters = privacy_cell_size_meters(level)
    if cell_size_meters is not None:
        coordinates = _collapse_consecutive_duplicates(
            [
                _approximate_coordinate(
                    lon,
                    lat,
                    cell_size_meters=cell_size_meters,
                )
                for lon, lat in coordinates
            ]
        )

    approximated_geometry = LineString(coordinates, srid=4326)
    return ApproximatedLine(
        geometry=approximated_geometry,
        distance_meters=_geography_length_meters(approximated_geometry),
    )


def line_geojson(approximated_line: ApproximatedLine | None) -> dict | None:
    if approximated_line is None:
        return None
    return {
        "type": "LineString",
        "coordinates": [
            [round(lon, 7), round(lat, 7)]
            for lon, lat in approximated_line.geometry.coords
        ],
    }


def approximate_point(
    point: Point | None,
    *,
    level: str,
) -> tuple[float, float] | None:

    if point is None:
        return None

    cell_size_meters = privacy_cell_size_meters(level)
    if cell_size_meters is None:
        return (float(point.x), float(point.y))
    return _approximate_coordinate(
        float(point.x),
        float(point.y),
        cell_size_meters=cell_size_meters,
    )


def point_geojson(coordinate: tuple[float, float] | None) -> dict | None:
    if coordinate is None:
        return None
    lon, lat = coordinate
    return {"type": "Point", "coordinates": [round(lon, 7), round(lat, 7)]}


#metriche per confrontare le viste
def privacy_metrics(
    geometry: LineString | None,
    *,
    level: str,
) -> PrivacyMetrics:
    if geometry is None:
        return PrivacyMetrics(0.0, 0.0, 0, 0.0, 0.0, 0.0)

    originals = [(float(lon), float(lat)) for lon, lat, *_ in geometry.coords]
    cell_size_meters = privacy_cell_size_meters(level)
    approximated = originals if cell_size_meters is None else [
        _approximate_coordinate(lon, lat, cell_size_meters=cell_size_meters)
        for lon, lat in originals
    ]

    perturbations = [
        haversine_meters(original[1], original[0], published[1], published[0])
        for original, published in zip(originals, approximated)
    ]
    approximated_geometry = LineString(
        _collapse_consecutive_duplicates(approximated),
        srid=4326,
    )
    private_distance, privacy_distance = _geography_lengths_meters(
        geometry,
        approximated_geometry,
    )
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

#Approssima il singolo punto gps
def _approximate_coordinate(
    lon: float,
    lat: float,
    *,
    cell_size_meters: int,
) -> tuple[float, float]:
    projected = Point(lon, lat, srid=4326)
    projected.transform(3857) # Web Mercator
    approximated = Point(
        math.floor(projected.x / cell_size_meters) * cell_size_meters
        + cell_size_meters / 2,
        math.floor(projected.y / cell_size_meters) * cell_size_meters
        + cell_size_meters / 2,
        srid=3857,
    )
    approximated.transform(4326)
    return approximated.x, approximated.y

#Lista di punti gps approssimati (molti duplicati) -> lista di punti gps diversi
def _collapse_consecutive_duplicates(
    coordinates: list[tuple[float, float]],
) -> list[tuple[float, float]]:
    collapsed: list[tuple[float, float]] = []
    for coordinate in coordinates:
        if not collapsed or coordinate != collapsed[-1]:
            collapsed.append(coordinate)
    #garantisce che ci siano almeno due punti
    if len(collapsed) == 1 and len(coordinates) > 1:
        return [collapsed[0], collapsed[0]]
    return collapsed


def _geography_length_meters(geometry: LineString) -> float:
    return _geography_lengths_meters(geometry)[0]


# Calcola con una sola query PostGIS la lunghezza di tutte le LineString.
def _geography_lengths_meters(*geometries: LineString) -> tuple[float, ...]:
    expressions = ", ".join(
        "ST_Length(%s::geography, true)" for _ in geometries
    )
    with connection.cursor() as cursor:
        cursor.execute(
            f"SELECT {expressions}",
            [geometry.ewkt for geometry in geometries],
        )
        return tuple(float(length) for length in cursor.fetchone())
