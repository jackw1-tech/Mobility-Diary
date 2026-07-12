"""Riconoscimento dei Luoghi Significativi: scoperta user-scoped dei luoghi.

Seam unico per il mining (PRD). Internamente, due fasi sostituibili:
  - detect_visits: stay-detection pura sui GpsPoint grezzi -> Visite Candidate.
  - mine_user_significant_places: ricomputo per-utente, serializzato (ADR 0027).

La scoperta parte SOLO dai GpsPoint grezzi (ADR 0029), dopo l'arricchimento
finale del diario (ADR 0020).
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

from django.contrib.gis.geos import Point
from django.db import connection, transaction
from django.db.models import Q

from .geo import haversine_meters
from .models import CandidateVisit, GpsPoint, HabitualPlace, MobilitySegment

# Soglie della stay-detection (motivazioni in relazione / PRD).
STAY_RADIUS_METERS = 75.0      # raggio della permanenza
MIN_STAY_SECONDS = 5 * 60      # permanenza minima
MIN_STAY_POINTS = 3            # punti validi minimi
# Gap di campionamento tollerato dentro una permanenza: pari alla permanenza
# minima, cosi' una sosta minima (3 punti su 5 min) non viene mai spezzata, ma
# un'interruzione piu' lunga della soglia apre un episodio distinto.
MAX_GAP_SECONDS = MIN_STAY_SECONDS
MAX_ACCURACY_METERS = 100.0    # i punti piu' imprecisi di cosi' vengono ignorati

# Clustering DBSCAN delle visite -> Luoghi Candidati (ADR 0022).
CLUSTER_EPS_METERS = 100.0                # soglia spaziale fra centroidi di visite
CLUSTER_MIN_VISITS = 3                    # cluster spaziale minimo per un luogo
MIN_CANDIDATE_DISTINCT_DAYS = 2           # un candidato richiede ritorno in piu' giorni
AUTO_CONFIRM_DISTINCT_DAYS = 3            # auto-conferma con evidenza su >= 3 giorni
# Proiezione metrica usata solo in query per il clustering spaziale lato PostGIS.
# ETRS89 / LAEA Europe mantiene un errore contenuto su scala europea senza
# cambiare il contratto WGS84/geography del dominio applicativo.
CLUSTER_PROJECTION_SRID = 3035

# Overlay read-time sul diario (ADR 0024): una sosta prende il Luogo Confermato
# piu' vicino entro questa soglia.
OVERLAY_MATCH_METERS = STAY_RADIUS_METERS
# Entro questa differenza di distanza due luoghi sono "in parita'": a parita'
# vince quello etichettato manualmente (PRD / ADR 0028).
OVERLAY_TIE_METERS = 25.0
NEUTRAL_PLACE_LABEL = "luogo abituale"

# Namespace per pg_advisory_xact_lock: isola il lock di mining da altri lock.
_MINING_LOCK_NAMESPACE = 0x5350  # "SP"


@dataclass(frozen=True)
class DetectedVisit:
    lat: float
    lon: float
    started_at: datetime
    ended_at: datetime
    point_count: int


@dataclass(frozen=True)
class VisibleStopSummary:
    lat: float
    lon: float
    matched_place: HabitualPlace | None


def _point_fields(point) -> tuple[datetime, Point, float | None]:
    """Rende omogeneo l'accesso ai campi minimi richiesti dalla stay-detection."""
    if hasattr(point, "timestamp"):
        return point.timestamp, point.point, getattr(point, "accuracy_meters", None)
    timestamp, geometry, *rest = point
    accuracy = rest[0] if rest else None
    return timestamp, geometry, accuracy

""" 
Algoritmo di stay detection (Pre processing per DBSCAN)
"""
def detect_visits(points) -> list[DetectedVisit]:
    visits: list[DetectedVisit] = []
    cluster_started_at: datetime | None = None
    cluster_ended_at: datetime | None = None
    point_count = 0
    sum_lat = 0.0
    sum_lon = 0.0

    def flush() -> None:
        if point_count < MIN_STAY_POINTS or cluster_started_at is None or cluster_ended_at is None:
            return
        if (cluster_ended_at - cluster_started_at).total_seconds() < MIN_STAY_SECONDS:
            return
        visits.append(
            DetectedVisit(
                lat=sum_lat / point_count,
                lon=sum_lon / point_count,
                started_at=cluster_started_at,
                ended_at=cluster_ended_at,
                point_count=point_count,
            )
        )

    for p in points:
        timestamp, point, accuracy_meters = _point_fields(p)
        if accuracy_meters is not None and accuracy_meters > MAX_ACCURACY_METERS:
            continue
        lat, lon = point.y, point.x
        if point_count:
            gap = (timestamp - cluster_ended_at).total_seconds()
            far = (
                haversine_meters(sum_lat / point_count, sum_lon / point_count, lat, lon)
                > STAY_RADIUS_METERS
            )
            if gap > MAX_GAP_SECONDS or far:
                flush()
                cluster_started_at = None
                cluster_ended_at = None
                point_count = 0
                sum_lat = sum_lon = 0.0
        if cluster_started_at is None:
            cluster_started_at = timestamp
        cluster_ended_at = timestamp
        point_count += 1
        sum_lat += lat
        sum_lon += lon
    flush()
    return visits

""" 
Funzione che prende tutti i GPS dei viaggi dell’utente X e scarta quelli imprecisi 
"""
def _user_points_for_detection(user_id: int):
    return (
        GpsPoint.objects.filter(trip__user_id=user_id)
        .filter(Q(accuracy_meters__isnull=True) | Q(accuracy_meters__lte=MAX_ACCURACY_METERS))
        .order_by("timestamp", "id")
        .values_list("timestamp", "point")
        .iterator(chunk_size=2000)
    )

""" 
GPS dell’utente -> visite candidate -> cluster di visite -> luoghi abituali
"""
def mine_user_significant_places(user_id: int) -> dict:
    with transaction.atomic():
        detected = detect_visits(_user_points_for_detection(user_id))
        manual_places = list(
            HabitualPlace.objects.filter(user_id=user_id, manually_reviewed=True)
        )
        CandidateVisit.objects.filter(user_id=user_id).delete()
        HabitualPlace.objects.filter(
            user_id=user_id, manually_reviewed=False
        ).delete()
        visits = CandidateVisit.objects.bulk_create(
            [
                CandidateVisit(
                    user_id=user_id,
                    center=Point(v.lon, v.lat, srid=4326),
                    started_at=v.started_at,
                    ended_at=v.ended_at,
                    point_count=v.point_count,
                )
                for v in detected
            ]
        )
        places = _cluster_into_places(user_id, visits, manual_places)
    return {"visits": len(visits), "places": places}


def _cluster_into_places(user_id: int, visits: list, manual_places: list) -> int:
    if not visits:
        return 0
    visit_by_id = {visit.pk: visit for visit in visits}
    clusters = _postgis_visit_clusters(visits)
    visits_to_update = []
    place_count = 0
    for cluster_visit_ids in clusters:
        cluster_visits = [visit_by_id[visit_id] for visit_id in cluster_visit_ids]
        place = _place_for_cluster(user_id, cluster_visits, manual_places)
        if place is None:
            continue
        place_count += 1
        for visit in cluster_visits:
            visit.place = place
        visits_to_update.extend(cluster_visits)
    if visits_to_update:
        CandidateVisit.objects.bulk_update(visits_to_update, ["place"])
    return place_count

""" 
DB SCAN
"""
def _postgis_visit_clusters(visits: list) -> list[list[int]]:

    table = CandidateVisit._meta.db_table
    visit_ids = [visit.pk for visit in visits]
    sql = f"""
        WITH clustered AS (
            SELECT
                id,
                ST_ClusterDBSCAN(
                    ST_Transform(center::geometry, %s),
                    eps => %s,
                    minpoints => %s
                ) OVER (ORDER BY id) AS cluster_id
            FROM {table}
            WHERE id = ANY(%s)
        )
        SELECT id, cluster_id
        FROM clustered
        WHERE cluster_id IS NOT NULL
        ORDER BY cluster_id, id
    """
    with connection.cursor() as cursor:
            cursor.execute(
                sql,
                [
                    CLUSTER_PROJECTION_SRID,
                    CLUSTER_EPS_METERS,
                    CLUSTER_MIN_VISITS,
                    visit_ids,
                ],
            )
            rows = cursor.fetchall()

    clusters: list[list[int]] = []
    current_cluster_id = None
    current_members: list[int] = []
    for visit_id, cluster_id in rows:
        if cluster_id != current_cluster_id:
            if current_members:
                clusters.append(current_members)
            current_cluster_id = cluster_id
            current_members = []
        current_members.append(visit_id)
    if current_members:
        clusters.append(current_members)
    return clusters


def _place_for_cluster(user_id: int, visits: list, manual_places: list) -> HabitualPlace | None:
    lats = [v.center.y for v in visits]
    lons = [v.center.x for v in visits]
    center_lat = sum(lats) / len(lats)
    center_lon = sum(lons) / len(lons)
    distinct_days = len({v.started_at.date() for v in visits})

    existing = _take_nearby_manual_place(center_lat, center_lon, manual_places)
    if existing is not None:
        # Reattach: rinfresca l'evidenza, conserva stato/etichetta/centro manuali.
        existing.visit_count = len(visits)
        existing.distinct_days = distinct_days
        existing.save(update_fields=["visit_count", "distinct_days", "updated_at"])
        return existing

    if distinct_days < MIN_CANDIDATE_DISTINCT_DAYS:
        return None

    radius = max(
        haversine_meters(center_lat, center_lon, lat, lon)
        for lat, lon in zip(lats, lons)
    )
    confirmed = distinct_days >= AUTO_CONFIRM_DISTINCT_DAYS
    return HabitualPlace.objects.create(
        user_id=user_id,
        center=Point(center_lon, center_lat, srid=4326),
        radius_meters=radius,
        state=(
            HabitualPlace.State.CONFIRMED
            if confirmed
            else HabitualPlace.State.CANDIDATE
        ),
        visit_count=len(visits),
        distinct_days=distinct_days,
    )


def _take_nearby_manual_place(lat: float, lon: float, manual_places: list):
    """Estrae (consumandolo) il luogo manuale entro la soglia di cluster, o None."""
    for place in manual_places:
        if haversine_meters(lat, lon, place.center.y, place.center.x) <= CLUSTER_EPS_METERS:
            manual_places.remove(place)
            return place
    return None


def place_label(place: HabitualPlace) -> str:
    """Etichetta del luogo: nome manuale > categoria > dicitura neutra (ADR 0023)."""
    return place.custom_name or place.category or NEUTRAL_PLACE_LABEL


def _is_manually_labeled(place: HabitualPlace) -> bool:
    return bool(place.custom_name or place.category)


def match_confirmed_place(lat: float, lon: float, places) -> HabitualPlace | None:
    """Il Luogo Confermato che meglio descrive (lat, lon), o None.

    `places` sono i Luoghi Confermati dell'utente. Vince il piu' vicino entro la
    soglia di overlay; a parita' effettiva di distanza (entro OVERLAY_TIE_METERS)
    vince un luogo etichettato manualmente su uno puramente automatico (ADR 0028).
    """
    within = [
        (haversine_meters(lat, lon, place.center.y, place.center.x), place)
        for place in places
    ]
    within = [(d, place) for d, place in within if d <= OVERLAY_MATCH_METERS]
    if not within:
        return None
    nearest = min(distance for distance, _ in within)
    contenders = [
        (distance, place)
        for distance, place in within
        if distance <= nearest + OVERLAY_TIE_METERS
    ]
    contenders.sort(
        key=lambda item: (0 if _is_manually_labeled(item[1]) else 1, item[0])
    )
    return contenders[0][1]


def _centroids_for_intervals(intervals, gps_points) -> dict[int, tuple[float, float] | None]:
    """Calcola in una sola scansione i centroidi degli intervalli richiesti."""
    ordered = sorted(
        intervals,
        key=lambda interval: (interval.start_timestamp, interval.end_timestamp),
    )
    stats = {id(interval): [0.0, 0.0, 0] for interval in ordered}
    active = []
    next_interval = 0

    for gps_point in gps_points:
        timestamp = gps_point.timestamp
        while (
            next_interval < len(ordered)
            and ordered[next_interval].start_timestamp <= timestamp
        ):
            active.append(ordered[next_interval])
            next_interval += 1

        if not active:
            continue

        still_active = []
        for interval in active:
            if interval.end_timestamp < timestamp:
                continue
            still_active.append(interval)
            stats[id(interval)][0] += gps_point.point.y
            stats[id(interval)][1] += gps_point.point.x
            stats[id(interval)][2] += 1
        active = still_active

    centroids = {}
    for interval in ordered:
        sum_lat, sum_lon, count = stats[id(interval)]
        centroids[id(interval)] = None if count == 0 else (sum_lat / count, sum_lon / count)
    return centroids


def stop_centroid(stop_like_interval, gps_points, centroid_cache=None) -> tuple[float, float] | None:
    if centroid_cache is not None:
        return centroid_cache.get(id(stop_like_interval))
    points = [
        g
        for g in gps_points
        if stop_like_interval.start_timestamp <= g.timestamp <= stop_like_interval.end_timestamp
    ]
    if not points:
        return None
    lat = sum(g.point.y for g in points) / len(points)
    lon = sum(g.point.x for g in points) / len(points)
    return lat, lon


def stop_like_source_intervals(segments, virtual_stop_intervals):
    return [
        *[
            segment
            for segment in segments
            if segment.kind == MobilitySegment.Kind.STOP
            or segment.activity_label == "IDLE"
        ],
        *virtual_stop_intervals,
    ]


def visible_stop_summary(
    visible_stop,
    source_intervals,
    gps_points,
    confirmed_places,
) -> VisibleStopSummary | None:
    relevant_intervals = [
        interval
        for interval in source_intervals
        if _intervals_touch_or_overlap(interval, visible_stop)
    ]
    if not relevant_intervals:
        return None

    intervals_for_centroids = {id(interval): interval for interval in relevant_intervals}
    intervals_for_centroids.setdefault(id(visible_stop), visible_stop)
    centroid_cache = _centroids_for_intervals(
        intervals_for_centroids.values(),
        gps_points,
    )
    centroids = [
        centroid
        for interval in relevant_intervals
        if (centroid := stop_centroid(interval, gps_points, centroid_cache)) is not None
    ]
    if not centroids:
        return None
    lat, lon = stop_centroid(visible_stop, gps_points, centroid_cache) or (
        sum(lat for lat, _ in centroids) / len(centroids),
        sum(lon for _, lon in centroids) / len(centroids),
    )
    matches = {
        match.id: match
        for centroid in centroids
        if (match := match_confirmed_place(*centroid, confirmed_places)) is not None
    }
    return VisibleStopSummary(
        lat=lat,
        lon=lon,
        matched_place=next(iter(matches.values())) if len(matches) == 1 else None,
    )


def visible_stop_place(visible_stop, source_intervals, gps_points, confirmed_places):
    summary = visible_stop_summary(
        visible_stop,
        source_intervals,
        gps_points,
        confirmed_places,
    )
    return None if summary is None else summary.matched_place


def _intervals_touch_or_overlap(first, second) -> bool:
    return (
        first.start_timestamp <= second.end_timestamp
        and second.start_timestamp <= first.end_timestamp
    )
