"""Repository del mining dei Luoghi Significativi.

Unico punto in cui compaiono `GpsPoint.objects`, `HabitualPlace.objects` (per
la fase di mining) e `CandidateVisit.objects`, incluso il DBSCAN spaziale via
SQL raw (che e' comunque una query, non una decisione di dominio). L'algoritmo
(stay-detection, clustering, riassegnazione manuale) resta in
`mobility.significant_places`.
"""

from __future__ import annotations

from django.contrib.gis.geos import Point
from django.db import connection
from django.db.models import Q

from ..models import CandidateVisit, GpsPoint, HabitualPlace

"""Restituisce ogni punto gps ordinato e scartando quelli con accuracy troppo alta"""
def points_for_stay_detection(user_id: int, *, max_accuracy_meters: float):
    return (
        GpsPoint.objects.filter(trip__user_id=user_id)
        .filter(
            Q(accuracy_meters__isnull=True)
            | Q(accuracy_meters__lte=max_accuracy_meters)
        )
        .order_by("timestamp", "id")
        .values_list("timestamp", "point")
        .iterator(chunk_size=2000)
    )

#Restituisce gli abutal place che io utente ho etichettato
def manually_reviewed_places_for_user(user_id: int) -> list[HabitualPlace]:
    return list(
        HabitualPlace.objects.filter(user_id=user_id, manually_reviewed=True)
    )


#Pulizia di tutti i candidate visit prima di reinserire quelle nuove
def delete_candidate_visits_for_user(user_id: int) -> None:
    CandidateVisit.objects.filter(user_id=user_id).delete()

#Pulizia di tutti gli habitual place non confermait prima di reinserire quelle nuove
def delete_unreviewed_places_for_user(user_id: int) -> None:
    HabitualPlace.objects.filter(
        user_id=user_id, manually_reviewed=False
    ).delete()

#Inserimento bulk di tutte le candidate visiti
def bulk_create_candidate_visits(visits: list[CandidateVisit]) -> list[CandidateVisit]:
    return CandidateVisit.objects.bulk_create(visits)


def bulk_update_visit_places(visits: list[CandidateVisit]) -> None:
    if visits:
        CandidateVisit.objects.bulk_update(visits, ["place"])


"""Aggiorna i dati dell'habitual place quando un nuovo habitual place appena calcolato corrisponde ad uno esistente"""
def refresh_place_evidence(
    place: HabitualPlace,
    *,
    visit_count: int,
    distinct_days: int,
) -> None:
    place.visit_count = visit_count
    place.distinct_days = distinct_days
    place.save(update_fields=["visit_count", "distinct_days", "updated_at"])


def create_habitual_place(
    *,
    user_id: int,
    center_lat: float,
    center_lon: float,
    radius_meters: float,
    state: str,
    visit_count: int,
    distinct_days: int,
) -> HabitualPlace:
    return HabitualPlace.objects.create(
        user_id=user_id,
        center=Point(center_lon, center_lat, srid=4326),
        radius_meters=radius_meters,
        state=state,
        visit_count=visit_count,
        distinct_days=distinct_days,
    )

"""DB SCAN"""
"""Restituice la lista delle candidate visit non isolate e il suo cluster id"""
def real_db_scan(
    visit_ids: list[int],
    *,
    projection_srid: int,
    eps_meters: float,
    min_visits: int,
) -> list[tuple[int, int]]:
    table = CandidateVisit._meta.db_table
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
            [projection_srid, eps_meters, min_visits, visit_ids],
        )
        return cursor.fetchall()
