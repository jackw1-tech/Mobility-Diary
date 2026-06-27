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

from .geo import haversine_meters
from .models import CandidateVisit, GpsPoint, HabitualPlace

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
CLUSTER_EPS_METERS = STAY_RADIUS_METERS  # soglia spaziale fra centroidi di visite
CLUSTER_MIN_VISITS = 2                    # un one-off isolato resta visita, non luogo
AUTO_CONFIRM_DISTINCT_DAYS = 3            # auto-conferma con evidenza su >= 3 giorni

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


def detect_visits(points) -> list[DetectedVisit]:
    """Stay-detection distance+time con centroide aggiornato.

    `points` sono GpsPoint ordinati per timestamp. Una permanenza nasce quando
    almeno MIN_STAY_POINTS punti restano entro STAY_RADIUS_METERS dal centroide
    corrente per almeno MIN_STAY_SECONDS; un punto troppo lontano o un gap
    temporale troppo lungo chiude la permanenza corrente e ne apre un'altra.
    """
    visits: list[DetectedVisit] = []
    cluster: list = []
    sum_lat = 0.0
    sum_lon = 0.0

    def flush() -> None:
        n = len(cluster)
        if n < MIN_STAY_POINTS:
            return
        if (cluster[-1].timestamp - cluster[0].timestamp).total_seconds() < MIN_STAY_SECONDS:
            return
        visits.append(
            DetectedVisit(
                lat=sum_lat / n,
                lon=sum_lon / n,
                started_at=cluster[0].timestamp,
                ended_at=cluster[-1].timestamp,
                point_count=n,
            )
        )

    for p in points:
        if p.accuracy_meters is not None and p.accuracy_meters > MAX_ACCURACY_METERS:
            continue  # punto troppo impreciso: ignorato prima della detection
        lat, lon = p.point.y, p.point.x
        if cluster:
            n = len(cluster)
            gap = (p.timestamp - cluster[-1].timestamp).total_seconds()
            far = haversine_meters(sum_lat / n, sum_lon / n, lat, lon) > STAY_RADIUS_METERS
            if gap > MAX_GAP_SECONDS or far:
                flush()
                cluster = []
                sum_lat = sum_lon = 0.0
        cluster.append(p)
        sum_lat += lat
        sum_lon += lon
    flush()
    return visits


def mine_user_significant_places(user_id: int) -> dict:
    """Ricomputo user-scoped delle Visite Candidate dalla storia GPS completa.

    Serializzato per utente con un advisory lock Postgres (ADR 0027): due viaggi
    che terminano insieme non producono visite in conflitto. Il ricomputo e'
    completo (ADR 0026): le visite dell'utente vengono rigenerate da zero.
    """
    with transaction.atomic():
        with connection.cursor() as cursor:
            cursor.execute(
                "SELECT pg_advisory_xact_lock(%s, %s)",
                [_MINING_LOCK_NAMESPACE, user_id],
            )
        points = list(
            GpsPoint.objects.filter(trip__user_id=user_id).order_by("timestamp", "id")
        )
        detected = detect_visits(points)
        # La review manuale sopravvive al ricomputo completo (ADR 0028): i luoghi
        # manuali non si cancellano, i cluster vicini si riagganciano a loro.
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
    """Clusterizza le visite in Luoghi Candidati e collega ogni visita al luogo."""
    coords = [(v.center.y, v.center.x) for v in visits]
    clusters = _dbscan(coords, CLUSTER_EPS_METERS, CLUSTER_MIN_VISITS)
    for members in clusters:
        cluster_visits = [visits[i] for i in members]
        place = _place_for_cluster(user_id, cluster_visits, manual_places)
        CandidateVisit.objects.filter(pk__in=[v.pk for v in cluster_visits]).update(
            place=place
        )
    return len(clusters)


def _place_for_cluster(user_id: int, visits: list, manual_places: list) -> HabitualPlace:
    """Riusa un luogo manuale vicino (reattach) o crea un nuovo Luogo automatico."""
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


def _dbscan(coords, eps_meters, min_samples) -> list[list[int]]:
    """DBSCAN sui centroidi delle visite (ADR 0022).

    `coords` e' una lista di (lat, lon). Ritorna i cluster come liste di indici;
    le visite isolate (one-off) restano rumore e non diventano Luoghi Candidati.
    """
    n = len(coords)
    neighbors = [
        [
            j
            for j in range(n)
            if haversine_meters(coords[i][0], coords[i][1], coords[j][0], coords[j][1])
            <= eps_meters
        ]
        for i in range(n)
    ]
    labels = [-1] * n
    next_cluster = 0
    for i in range(n):
        if labels[i] != -1 or len(neighbors[i]) < min_samples:
            continue
        labels[i] = next_cluster
        queue = list(neighbors[i])
        while queue:
            j = queue.pop()
            if labels[j] != -1:
                continue
            labels[j] = next_cluster
            if len(neighbors[j]) >= min_samples:
                queue.extend(neighbors[j])
        next_cluster += 1
    clusters: list[list[int]] = [[] for _ in range(next_cluster)]
    for index, label in enumerate(labels):
        if label != -1:
            clusters[label].append(index)
    return clusters


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
