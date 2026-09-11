from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

from django.contrib.gis.geos import Point
from django.db import transaction

from .diary_projection import ProjectedDiarySegment, project_diary_segments
from .geo import haversine_meters
from .models import CandidateVisit, HabitualPlace, MobilitySegment
from .selectors import place_mining as place_mining_repository


STAY_RADIUS_METERS = 75.0      # raggio della permanenza
MIN_STAY_SECONDS = 5 * 60      # permanenza minima
MIN_STAY_POINTS = 3            # punti validi minimi
MAX_GAP_SECONDS = 90 * 60      # buco massimo tra due punti GPS nella stessa sosta
MAX_ACCURACY_METERS = 60.0

CLUSTER_EPS_METERS = 100.0                # soglia spaziale fra centroidi di visite
CLUSTER_MIN_VISITS = 3                    # cluster spaziale minimo per un luogo
MIN_CANDIDATE_DISTINCT_DAYS = 2           # un candidato richiede ritorno in piu' giorni
AUTO_CONFIRM_DISTINCT_DAYS = 4           # auto-conferma con evidenza su >= 3 giorni
CLUSTER_SRID = 3035


MIN_MATCH_RADIUS_METERS = STAY_RADIUS_METERS  # pavimento minimo, indipendente dal radius_meters del luogo
NEUTRAL_PLACE_LABEL = "luogo abituale"

@dataclass(frozen=True)
class DetectedVisit:
    lat: float
    lon: float
    started_at: datetime
    ended_at: datetime
    point_count: int


@dataclass(frozen=True)
class VisibleStopDetails:
    lat: float
    lon: float
    matched_place: HabitualPlace | None


"""
Algoritmo di stay detection (Pre processing per DBSCAN)
"""
def detect_visits(points: list[tuple[datetime, Point]]) -> list[DetectedVisit]:
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

    for timestamp, point in points:
        lat, lon = point.y, point.x
        if point_count: # c'è già un cluster in costruzione
            gap = (timestamp - cluster_ended_at).total_seconds()
            far = (
                haversine_meters(sum_lat / point_count, sum_lon / point_count, lat, lon)
                > STAY_RADIUS_METERS
            )
            if gap > MAX_GAP_SECONDS or far: #se è passato troppo tempo oppure i punti sono troppo lontani
                flush()
                cluster_started_at = None
                cluster_ended_at = None
                point_count = 0
                sum_lat = sum_lon = 0.0
        if cluster_started_at is None: # Ricomincia un nuovo cluster
            cluster_started_at = timestamp
        cluster_ended_at = timestamp
        point_count += 1
        sum_lat += lat
        sum_lon += lon
    flush()
    return visits

"""
GPS dell’utente -> visite candidate -> cluster di visite -> luoghi abituali
"""
def mine_user_significant_places(user_id: int) -> dict:
    with transaction.atomic():
        detected = detect_visits(
            list(
                place_mining_repository.points_for_stay_detection(
                    user_id,
                    max_accuracy_meters=MAX_ACCURACY_METERS,
                )
            )
        )
        manual_places = place_mining_repository.manually_reviewed_places_for_user(
            user_id
        )
        place_mining_repository.delete_candidate_visits_for_user(user_id)
        place_mining_repository.delete_unreviewed_places_for_user(user_id)
        visits = place_mining_repository.bulk_create_candidate_visits(
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


"""
Chiama Db Scan e inserisce nel db tutti gli habitual place
"""
def _cluster_into_places(user_id: int, visits: list, manual_places: list) -> int:
    if not visits:
        return 0
    visit_by_id = {visit.pk: visit for visit in visits}
    clusters = _dbscan_wrapper(list(visit_by_id))
    visits_to_update = []
    place_count = 0
    for cluster_visit_ids in clusters:
        cluster_visits = [visit_by_id[visit_id] for visit_id in cluster_visit_ids]
        place = create_habitual_place_for_cluster(user_id, cluster_visits, manual_places)
        if place is None:
            continue
        place_count += 1
        for visit in cluster_visits:
            visit.place = place
        visits_to_update.extend(cluster_visits)
    place_mining_repository.bulk_update_visit_places(visits_to_update)
    return place_count

"""
Funzione che chiama DB SCAN
"""
def _dbscan_wrapper(visit_ids: list[int]) -> list[list[int]]:
    rows = place_mining_repository.real_db_scan(
        visit_ids,
        projection_srid=CLUSTER_SRID,
        eps_meters=CLUSTER_EPS_METERS,
        min_visits=CLUSTER_MIN_VISITS,
    )

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


#Crea una nuova habitual place partendo da una lista di candidate visit di un cluster
def create_habitual_place_for_cluster(user_id: int, visits: list, manual_places: list) -> HabitualPlace | None:
    lats = [v.center.y for v in visits]
    lons = [v.center.x for v in visits]
    center_lat = sum(lats) / len(lats)
    center_lon = sum(lons) / len(lons)
    distinct_days = len({v.started_at.date() for v in visits}) #giorni diversi

    existing = _take_nearby_manual_place(center_lat, center_lon, manual_places)
    if existing is not None:
        place_mining_repository.refresh_place_evidence(
            existing,
            visit_count=len(visits),
            distinct_days=distinct_days,
        )
        return existing

    if distinct_days < MIN_CANDIDATE_DISTINCT_DAYS:
        return None #Per essere davvero un luogo abituale, mi ci devo fermare alemno 2 giorni diversi

    radius = max(
        haversine_meters(center_lat, center_lon, lat, lon)
        for lat, lon in zip(lats, lons)
    )
    confirmed = distinct_days >= AUTO_CONFIRM_DISTINCT_DAYS # Autoconferma dopo 4 giorni
    return place_mining_repository.create_habitual_place(
        user_id=user_id,
        center_lat=center_lat,
        center_lon=center_lon,
        radius_meters=radius,
        state=(
            HabitualPlace.State.CONFIRMED
            if confirmed
            else HabitualPlace.State.CANDIDATE
        ),
        visit_count=len(visits),
        distinct_days=distinct_days,
    )

"""Cerca di associare l'habitual place appena calcolato ad un luogo già confermato dall'utente"""
def _take_nearby_manual_place(lat: float, lon: float, manual_places: list):
    for place in manual_places:
        if haversine_meters(lat, lon, place.center.y, place.center.x) <= CLUSTER_EPS_METERS:
            manual_places.remove(place)
            return place
    return None


def place_label(place: HabitualPlace) -> str:
    return place.custom_name or place.category or NEUTRAL_PLACE_LABEL


# Prendo la latitutine e longitudine del centroide del mio singolo segmento di stop (virtual oppure vero stop)
# e restituisco il place più vicno
def match_confirmed_place(lat: float, lon: float, places) -> HabitualPlace | None:
    within = [
        (haversine_meters(lat, lon, place.center.y, place.center.x), place)
        for place in places
    ]
    within = [
        (d, place)
        for d, place in within
        if d <= max(place.radius_meters, MIN_MATCH_RADIUS_METERS) #DB Scan può creare cluster "a catena", quindi può capitare che il radius sia > soglia minima di una vista candidata
    ]
    if not within:
        return None
    return min(within, key=lambda item: item[0])[1]


# Per ogni intervallo calcola quanti punti gps li riguardano e fa una media di latitudine e lontitudine
def stop_centroid(stop_like_interval, gps_points) -> tuple[float, float] | None:
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

"""Associa ad un segmento di stop un place confermato, usando il centroide
GPS dell'intero periodo di sosta (non dei singoli pezzi grezzi che lo compongono).
"""
def visible_stop_details(
    visible_stop,
    gps_points,
    confirmed_places,
) -> VisibleStopDetails | None:
    centroid = stop_centroid(visible_stop, gps_points)
    if centroid is None:
        return None
    lat, lon = centroid
    return VisibleStopDetails(
        lat=lat,
        lon=lon,
        matched_place=match_confirmed_place(lat, lon, confirmed_places),
    )

# unisco segmenti reali e stop virtuali e associo ad ogni stop un place
def project_diary_with_places(
    persisted_segments,
    virtual_stop_intervals,
    gps_points,
    confirmed_places,
) -> list[tuple[ProjectedDiarySegment, VisibleStopDetails | None]]:
    return [
        (
            segment,
            visible_stop_details(segment, gps_points, confirmed_places)
            if segment.kind == MobilitySegment.Kind.STOP
            else None,
        )
        for segment in project_diary_segments(persisted_segments, virtual_stop_intervals)
    ]
