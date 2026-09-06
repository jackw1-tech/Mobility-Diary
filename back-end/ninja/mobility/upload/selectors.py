from __future__ import annotations

from django.db.models import QuerySet

from ..models import Trip, TripUpload, TripUploadPart


""" 
Ottiene tutti i raw parts completati di un trip
"""
def completed_raw_parts_for_trip(trip: Trip) -> QuerySet[TripUploadPart]:
    return TripUploadPart.objects.filter(
        upload__trip=trip,
        upload__raw_status=TripUpload.PhaseStatus.COMPLETED,
        received_at__isnull=False,
    ).order_by("sequence", "id")


def create_upload_part(
    upload: TripUpload,
    *,
    sequence: int,
    sha256: str,
    object_key: str,
    received_at,
) -> TripUploadPart:
    return TripUploadPart.objects.create(
        upload=upload,
        sequence=sequence,
        sha256=sha256,
        object_key=object_key,
        received_at=received_at,
    )


def get_or_create_upload_part(
    upload: TripUpload,
    *,
    sequence: int,
    defaults: dict,
) -> tuple[TripUploadPart, bool]:
    return TripUploadPart.objects.select_for_update().get_or_create(
        upload=upload,
        sequence=sequence,
        defaults=defaults,
    )


def upload_part_by_sequence(
    upload: TripUpload, sequence: int
) -> TripUploadPart | None:
    return TripUploadPart.objects.filter(
        upload=upload, sequence=sequence
    ).first()


def mark_part_received(part: TripUploadPart, *, received_at) -> None:
    part.received_at = received_at
    part.save(update_fields=["received_at"])


def owned_uploads_for_owner(user_id: int) -> QuerySet[TripUpload]:
    return TripUpload.objects.select_related("trip").filter(user_id=user_id)

""" 
Prende una trip uploads solo se appartiene all'utente autenticato
"""
def active_uploads_for_owner(user_id: int) -> QuerySet[TripUpload]:
    return owned_uploads_for_owner(user_id).filter(
        recording_started_at__isnull=False,
        recording_closed_at__isnull=True,
        recording_abandoned_at__isnull=True,
    )


"""
Controlla se un utente ha già una registrazione attiva in corso
Se ancora in corso, ottiene il lock su quella riga
"""
def locked_active_uploads_for_owner(user_id: int) -> QuerySet[TripUpload]:
    return TripUpload.objects.filter(
        user_id=user_id,
        recording_started_at__isnull=False,
        recording_closed_at__isnull=True,
        recording_abandoned_at__isnull=True,
    ).select_for_update()


def create_upload(
    *,
    user_id: int,
    client_session_id: str,
    device_id: str,
    started_at,
    recording_started_at,
    last_seen_at,
    source_trip_id: int | None,
) -> TripUpload:
    return TripUpload.objects.create(
        user_id=user_id,
        client_session_id=client_session_id,
        device_id=device_id,
        started_at=started_at,
        recording_started_at=recording_started_at,
        last_seen_at=last_seen_at,
        source_trip_id=source_trip_id,
    )


def upload_with_trip(upload_id: int) -> TripUpload:
    return TripUpload.objects.select_related("trip").get(id=upload_id)

# Blocca la riga
def locked_upload_by_id(upload_id: int) -> TripUpload:
    return TripUpload.objects.select_for_update().get(id=upload_id)


def owned_upload(user_id: int, upload_id: int) -> TripUpload | None:
    return TripUpload.objects.filter(user_id=user_id, id=upload_id).first()


def locked_owned_upload(user_id: int, upload_id: int) -> TripUpload | None:
    return (
        TripUpload.objects.filter(user_id=user_id, id=upload_id)
        .select_for_update()
        .first()
    )


def locked_upload_by_client_session(
    user_id: int, client_session_id: str
) -> TripUpload | None:
    return (
        TripUpload.objects.select_for_update()
        .filter(user_id=user_id, client_session_id=client_session_id)
        .first()
    )


def create_upload_with_fields(**fields) -> TripUpload:
    return TripUpload.objects.create(**fields)


def delete_upload(upload: TripUpload) -> None:
    upload.delete()
