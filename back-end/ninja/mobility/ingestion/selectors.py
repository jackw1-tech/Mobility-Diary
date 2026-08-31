from __future__ import annotations

from django.db.models import QuerySet

from ..models import Trip, TripIngestion, TripIngestionPart


""" 
Ottiene tutti i raw parts completati di un trip
"""
def completed_raw_parts_for_trip(trip: Trip) -> QuerySet[TripIngestionPart]:
    return TripIngestionPart.objects.filter(
        ingestion__trip=trip,
        ingestion__raw_status=TripIngestion.PhaseStatus.COMPLETED,
        received_at__isnull=False,
    ).order_by("sequence", "id")


def create_ingestion_part(
    ingestion: TripIngestion,
    *,
    sequence: int,
    sha256: str,
    size_bytes: int,
    object_key: str,
    received_at,
) -> TripIngestionPart:
    return TripIngestionPart.objects.create(
        ingestion=ingestion,
        sequence=sequence,
        sha256=sha256,
        size_bytes=size_bytes,
        object_key=object_key,
        received_at=received_at,
    )


def get_or_create_ingestion_part(
    ingestion: TripIngestion,
    *,
    sequence: int,
    defaults: dict,
) -> tuple[TripIngestionPart, bool]:
    return TripIngestionPart.objects.select_for_update().get_or_create(
        ingestion=ingestion,
        sequence=sequence,
        defaults=defaults,
    )


def ingestion_part_by_sequence(
    ingestion: TripIngestion, sequence: int
) -> TripIngestionPart | None:
    return TripIngestionPart.objects.filter(
        ingestion=ingestion, sequence=sequence
    ).first()


def mark_part_received(part: TripIngestionPart, *, received_at) -> None:
    part.received_at = received_at
    part.save(update_fields=["received_at"])


def owned_ingestions_for_owner(user_id: int) -> QuerySet[TripIngestion]:
    return TripIngestion.objects.select_related("trip").filter(user_id=user_id)

""" 
Prende una trip ingestions solo se appartiene all'utente autenticato
"""
def active_ingestions_for_owner(user_id: int) -> QuerySet[TripIngestion]:
    return owned_ingestions_for_owner(user_id).filter(
        recording_started_at__isnull=False,
        recording_closed_at__isnull=True,
        recording_abandoned_at__isnull=True,
    )


"""
Controlla se un utente ha già una registrazione attiva in corso
Se ancora in corso, ottiene il lock su quella riga
"""
def locked_active_ingestions_for_owner(user_id: int) -> QuerySet[TripIngestion]:
    return TripIngestion.objects.filter(
        user_id=user_id,
        recording_started_at__isnull=False,
        recording_closed_at__isnull=True,
        recording_abandoned_at__isnull=True,
    ).select_for_update()


def create_ingestion(
    *,
    user_id: int,
    client_session_id: str,
    device_id: str,
    started_at,
    recording_started_at,
    last_seen_at,
    source_trip_id: int | None,
) -> TripIngestion:
    return TripIngestion.objects.create(
        user_id=user_id,
        client_session_id=client_session_id,
        device_id=device_id,
        started_at=started_at,
        recording_started_at=recording_started_at,
        last_seen_at=last_seen_at,
        source_trip_id=source_trip_id,
    )


def ingestion_with_trip(ingestion_id: int) -> TripIngestion:
    return TripIngestion.objects.select_related("trip").get(id=ingestion_id)


def locked_ingestion_by_id(ingestion_id: int) -> TripIngestion:
    return TripIngestion.objects.select_for_update().get(id=ingestion_id)


def owned_ingestion(user_id: int, ingestion_id: int) -> TripIngestion | None:
    return TripIngestion.objects.filter(user_id=user_id, id=ingestion_id).first()


def locked_owned_ingestion(user_id: int, ingestion_id: int) -> TripIngestion | None:
    return (
        TripIngestion.objects.filter(user_id=user_id, id=ingestion_id)
        .select_for_update()
        .first()
    )


def locked_ingestion_by_client_session(
    user_id: int, client_session_id: str
) -> TripIngestion | None:
    return (
        TripIngestion.objects.select_for_update()
        .filter(user_id=user_id, client_session_id=client_session_id)
        .first()
    )


def create_ingestion_with_fields(**fields) -> TripIngestion:
    """Crea una TripIngestion con i campi indicati (nessuna decisione qui)."""
    return TripIngestion.objects.create(**fields)


def delete_ingestion(ingestion: TripIngestion) -> None:
    ingestion.delete()
