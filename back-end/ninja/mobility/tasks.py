import gzip
import json

from celery import shared_task
from django.contrib.gis.geos import Point
from django.db import transaction
from django.utils import timezone
from django.utils.dateparse import parse_datetime

from .ingestion import storage
from .models import (
    GpsPoint,
    HarJob,
    PartKind,
    StateTransition,
    Trip,
    TripIngestion,
)
from .ml.pipeline import run_pipeline


@shared_task(bind=True)
def process_trip_har(self, job_id: int) -> dict:
    job = HarJob.objects.select_related("trip").get(id=job_id)
    job.status = HarJob.Status.STARTED
    job.save(update_fields=["status", "updated_at"])

    trip = job.trip

    # Idempotenza: se il diario e gia stato prodotto, non rielaborare.
    if trip.status == Trip.Status.PROCESSED:
        result = {"skipped": "trip already processed"}
        job.status = HarJob.Status.SUCCESS
        job.result = result
        job.save(update_fields=["status", "result", "updated_at"])
        return result

    try:
        result = run_pipeline(trip)
    except Exception as exc:  # noqa: BLE001
        job.status = HarJob.Status.FAILURE
        job.error = str(exc)
        job.save(update_fields=["status", "error", "updated_at"])
        raise

    job.status = HarJob.Status.SUCCESS
    job.result = result
    job.save(update_fields=["status", "result", "updated_at"])
    return result


# --------------------------------------------------------------------------- #
# Ingestione asincrona (REPORT_STRATEGIA_INGESTION_ASINCRONA.md)
# --------------------------------------------------------------------------- #


def _load_json_gz(object_key: str) -> dict:
    """Scarica e decomprime un blob .json.gz dallo storage."""
    raw = storage.read_object(object_key)
    return json.loads(gzip.decompress(raw).decode("utf-8"))


def _materialize_gps(trip: Trip, ingestion: TripIngestion) -> int:
    part = ingestion.parts.filter(
        kind=PartKind.GPS_POINTS, received_at__isnull=False
    ).first()
    if part is None:
        return 0

    payload = _load_json_gz(part.object_key)
    rows = []
    for p in payload.get("points", []):
        lat = p.get("latitude")
        lon = p.get("longitude")
        if lat is None or lon is None:
            continue
        rows.append(
            GpsPoint(
                trip=trip,
                timestamp=parse_datetime(p["timestamp"]),
                point=Point(float(lon), float(lat), srid=4326),
                speed_mps=p.get("speed_mps") or 0,
                accuracy_meters=p.get("accuracy_meters"),
            )
        )
    GpsPoint.objects.bulk_create(rows, ignore_conflicts=True)
    return len(rows)


def _materialize_transitions(trip: Trip, ingestion: TripIngestion) -> int:
    part = ingestion.parts.filter(
        kind=PartKind.STATE_TRANSITIONS, received_at__isnull=False
    ).first()
    if part is None:
        return 0

    payload = _load_json_gz(part.object_key)
    rows = [
        StateTransition(
            trip=trip,
            from_state=t["from_state"],
            to_state=t["to_state"],
            reason=t.get("reason", ""),
            timestamp=parse_datetime(t["timestamp"]),
            sigma=t.get("sigma"),
            speed_mps=t.get("speed_mps"),
        )
        for t in payload.get("transitions", [])
    ]
    StateTransition.objects.bulk_create(rows, ignore_conflicts=True)
    return len(rows)


@shared_task(bind=True, max_retries=3, default_retry_delay=30)
def process_trip_ingestion(self, ingestion_id: int) -> dict:
    """Materializza un Trip pulito da una TripIngestion completata.

    Legge solo i blob leggeri (GPS + transizioni) e li scrive su PostGIS in una
    transazione atomica. Le sensor window NON entrano in Postgres: restano blob
    nello storage in attesa di HAR (REPORT D4/D8).

    CONGELATO (D9): HAR finale non viene invocato e i blob raw NON vengono mai
    cancellati. Lo stato terminale attuale e' PROCESSED.
    """
    ingestion = TripIngestion.objects.select_related("user").get(id=ingestion_id)

    # Idempotenza: se gia' materializzato, non rifare.
    if ingestion.status in {
        TripIngestion.Status.PROCESSED,
        TripIngestion.Status.COMPLETED,
    }:
        return {"skipped": f"ingestion already {ingestion.status}"}

    ingestion.status = TripIngestion.Status.PROCESSING
    ingestion.started_processing_at = timezone.now()
    ingestion.save(update_fields=["status", "started_processing_at", "updated_at"])

    try:
        with transaction.atomic():
            trip, _ = Trip.objects.get_or_create(
                client_session_id=ingestion.client_session_id,
                defaults={
                    "user_id": ingestion.user_id,
                    "device_id": ingestion.device_id or "unknown",
                    "status": Trip.Status.CLOSED,
                },
            )
            # Il viaggio e' concluso lato client: assicura stato/chiusura.
            if trip.status == Trip.Status.OPEN:
                trip.status = Trip.Status.CLOSED
            trip.ended_at = ingestion.ended_at or trip.ended_at or timezone.now()
            trip.save(update_fields=["status", "ended_at", "updated_at"])

            gps_count = _materialize_gps(trip, ingestion)
            transition_count = _materialize_transitions(trip, ingestion)

            ingestion.trip = trip
            ingestion.status = TripIngestion.Status.PROCESSED
            ingestion.error_message = ""
            ingestion.completed_at = timezone.now()
            ingestion.save(
                update_fields=[
                    "trip",
                    "status",
                    "error_message",
                    "completed_at",
                    "updated_at",
                ]
            )
    except Exception as exc:  # noqa: BLE001
        will_retry = self.request.retries < self.max_retries
        ingestion.status = (
            TripIngestion.Status.FAILED_RETRYABLE
            if will_retry
            else TripIngestion.Status.FAILED_FINAL
        )
        ingestion.error_message = str(exc)
        ingestion.failed_at = timezone.now()
        ingestion.save(update_fields=["status", "error_message", "failed_at", "updated_at"])
        if will_retry:
            raise self.retry(exc=exc)
        raise

    # CONGELATO: qui in futuro andra' `process_trip_har_final.delay(trip.id, ingestion.id)`.
    # Per ora HAR non viene invocato e i blob raw restano nello storage.
    return {
        "trip_id": trip.id,
        "gps_points": gps_count,
        "state_transitions": transition_count,
    }


@shared_task(bind=True)
def process_trip_har_final(self, trip_id: int, ingestion_id: int) -> dict:
    """[CONGELATO — predisposto ma non attivo]

    In futuro: legge le sensor window blob dallo storage, esegue HAR finale,
    scrive label/segmenti, e SOLO on-success cancella i blob raw (D9).
    Finche' HAR non e' integrato questo task non viene mai accodato.
    """
    raise NotImplementedError(
        "process_trip_har_final e' congelato: HAR finale non ancora integrato (REPORT D9)."
    )
