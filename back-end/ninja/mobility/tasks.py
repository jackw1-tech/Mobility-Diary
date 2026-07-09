import logging
import time
from typing import Any

from celery import shared_task
from django.db import transaction
from django.utils import timezone

from .diary_events import (
    DIARY_ENRICHMENT_FAILED_REASON,
    DIARY_STATUS_ENRICHED,
    DIARY_STATUS_FAILED,
    publish_diary_status_on_commit,
)
from .ingestion.raw_sensor_codec import InvalidRawSensorPayload
from .ingestion.raw_sensor_loader import load_raw_sensor_windows
from .ingestion.services import process_part_based_core_ingestion
from .models import (
    HarJob,
    PlaceMiningStatus,
    Trip,
    TripIngestion,
)
from .ml.pipeline import run_pipeline
from .services.har import run_har_pipeline_with_timings
from .significant_places import mine_user_significant_places

logger = logging.getLogger(__name__)


RAW_CLAIMABLE_STATUSES = {
    TripIngestion.PhaseStatus.QUEUED,
    TripIngestion.PhaseStatus.FAILED_RETRYABLE,
}
_PLACE_MINING_PENDING_FIELDS = [
    "status",
    "requested_at",
    "started_at",
    "finished_at",
    "error_message",
    "rerun_requested",
]
_HAR_TIMING_FIELDS = [
    "claim_ms",
    "raw_parts_query_ms",
    "raw_s3_read_ms",
    "raw_gzip_ms",
    "raw_json_ms",
    "raw_binary_decode_ms",
    "raw_window_parse_ms",
    "raw_sort_ms",
    "raw_load_total_ms",
    "pipeline_load_inputs_ms",
    "pipeline_normalize_ms",
    "pipeline_window_speed_ms",
    "pipeline_classify_ms",
    "pipeline_gps_correction_ms",
    "pipeline_segment_db_ms",
    "pipeline_result_counts_ms",
    "pipeline_total_ms",
    "success_update_ms",
    "total_ms",
]


def _add_elapsed_ms(timings: dict[str, Any] | None, key: str, start: float) -> None:
    if timings is None:
        return
    elapsed = (time.perf_counter() - start) * 1000
    timings[key] = round(float(timings.get(key, 0.0)) + elapsed, 2)


def _log_har_timing(
    *,
    ingestion_id: int,
    job_id: int,
    trip_id: int,
    timings: dict[str, Any],
    result: dict | None = None,
) -> None:
    values = [
        f"{field}={timings[field]}"
        for field in _HAR_TIMING_FIELDS
        if field in timings
    ]
    logger.info(
        "HAR_TIMING ingestion_id=%s job_id=%s trip_id=%s raw_parts=%s "
        "windows=%s %s",
        ingestion_id,
        job_id,
        trip_id,
        timings.get("raw_parts", 0),
        (result or {}).get("windows", timings.get("raw_windows", 0)),
        " ".join(values),
    )


def _skip_result(phase: str, status: str) -> dict:
    return {"skipped": f"{phase} ingestion is {status}"}


def _place_mining_status_for_update(user_id: int) -> PlaceMiningStatus:
    status, _ = PlaceMiningStatus.objects.get_or_create(
        user_id=user_id,
        defaults={
            "status": PlaceMiningStatus.Status.IDLE,
            "requested_at": timezone.now(),
        },
    )
    return PlaceMiningStatus.objects.select_for_update().get(pk=status.pk)


def _save_place_mining_status(status: PlaceMiningStatus, *fields: str) -> None:
    status.save(update_fields=[*fields, "updated_at"])


def _set_place_mining_pending(
    status: PlaceMiningStatus,
    *,
    requested_at,
    rerun_requested: bool,
    error_message: str = "",
) -> None:
    status.status = PlaceMiningStatus.Status.PENDING
    status.requested_at = requested_at
    status.started_at = None
    status.finished_at = None
    status.error_message = error_message
    status.rerun_requested = rerun_requested
    _save_place_mining_status(status, *_PLACE_MINING_PENDING_FIELDS)


def _request_place_mining(user_id: int | None) -> bool:
    """Ritorna True solo quando va davvero accodata una nuova run."""
    if user_id is None:
        return False
    with transaction.atomic():
        status = _place_mining_status_for_update(user_id)
        now = timezone.now()
        if status.status in {
            PlaceMiningStatus.Status.PENDING,
            PlaceMiningStatus.Status.RUNNING,
        }:
            status.requested_at = now
            status.rerun_requested = True
            _save_place_mining_status(status, "requested_at", "rerun_requested")
            return False
        _set_place_mining_pending(
            status,
            requested_at=now,
            rerun_requested=False,
        )
        return True


def _begin_place_mining_run(user_id: int) -> bool:
    with transaction.atomic():
        status = _place_mining_status_for_update(user_id)
        if status.status != PlaceMiningStatus.Status.PENDING:
            return False
        status.status = PlaceMiningStatus.Status.RUNNING
        status.started_at = timezone.now()
        status.finished_at = None
        status.error_message = ""
        _save_place_mining_status(
            status,
            "status",
            "started_at",
            "finished_at",
            "error_message",
        )
        return True


def _finish_place_mining_run(
    user_id: int,
    *,
    status_value: str,
    error_message: str = "",
) -> bool:
    """Chiude la run corrente e ritorna True se va schedulato un follow-up."""
    with transaction.atomic():
        status = _place_mining_status_for_update(user_id)
        if status.rerun_requested:
            _set_place_mining_pending(
                status,
                requested_at=timezone.now(),
                rerun_requested=False,
            )
            return True
        status.status = status_value
        status.finished_at = timezone.now()
        status.error_message = error_message
        status.rerun_requested = False
        _save_place_mining_status(
            status,
            "status",
            "finished_at",
            "error_message",
            "rerun_requested",
        )
        return False


def _mark_place_mining_retryable(user_id: int | None, exc: Exception) -> None:
    if user_id is None:
        return
    with transaction.atomic():
        status = _place_mining_status_for_update(user_id)
        _set_place_mining_pending(
            status,
            requested_at=status.requested_at or timezone.now(),
            rerun_requested=status.rerun_requested,
            error_message=str(exc),
        )


@shared_task(bind=True, max_retries=3, retry_backoff=True)
def mine_significant_places(self, user_id: int) -> dict:
    """Riconoscimento dei Luoghi Significativi user-scoped (passo finale async)."""
    if not _begin_place_mining_run(user_id):
        return {"skipped": "place mining not pending"}
    try:
        result = mine_user_significant_places(user_id)
    except Exception as exc:  # noqa: BLE001
        will_retry = self.request.retries < self.max_retries
        if will_retry:
            _mark_place_mining_retryable(user_id, exc)
            raise self.retry(exc=exc)
        if _finish_place_mining_run(
            user_id,
            status_value=PlaceMiningStatus.Status.FAILED,
            error_message=str(exc),
        ):
            _schedule_place_mining(user_id)
        raise
    if _finish_place_mining_run(
        user_id,
        status_value=PlaceMiningStatus.Status.SUCCEEDED,
    ):
        _schedule_place_mining(user_id)
    return result


def _schedule_place_mining(user_id: int | None) -> None:
    """Accoda il mining dei luoghi dopo il commit dell'arricchimento (ADR 0020)."""
    if user_id is not None:
        transaction.on_commit(lambda: mine_significant_places.delay(user_id))


def _after_har_success(trip: Trip) -> None:
    should_schedule = _request_place_mining(trip.user_id)
    publish_diary_status_on_commit(trip.id, DIARY_STATUS_ENRICHED)
    if should_schedule:
        _schedule_place_mining(trip.user_id)


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
    _after_har_success(trip)
    return result


# --------------------------------------------------------------------------- #
# Ingestione asincrona (REPORT_STRATEGIA_INGESTION_ASINCRONA.md)
# --------------------------------------------------------------------------- #


@shared_task(bind=True, max_retries=3, default_retry_delay=30)
def process_trip_ingestion(self, ingestion_id: int) -> dict:
    """Materializza un Trip pulito da una TripIngestion completata.

    Legge solo i blob leggeri (GPS + transizioni) e li scrive su PostGIS in una
    transazione atomica. Le sensor window NON entrano in Postgres: restano blob
    nello storage in attesa di HAR (REPORT D4/D8).

    La fase HAR finale e separata: dopo il completamento core, `complete-raw`
    accoda `process_trip_har_final` quando tutte le sensor window sono arrivate.
    I blob raw NON vengono cancellati in questa fase del progetto.
    """
    try:
        return process_part_based_core_ingestion(
            ingestion_id,
            will_retry_on_error=self.request.retries < self.max_retries,
        )
    except Exception as exc:  # noqa: BLE001
        if self.request.retries < self.max_retries:
            raise self.retry(exc=exc)
        raise


@shared_task(bind=True, max_retries=3, default_retry_delay=30)
def process_trip_har_final(self, job_id: int, ingestion_id: int) -> dict:
    """Elabora i raw sensori dal bucket e rigenera il Diario della Mobilita."""
    timings: dict[str, Any] = {}
    total_start = time.perf_counter()
    claim_start = time.perf_counter()
    with transaction.atomic():
        ingestion = (
            TripIngestion.objects.select_for_update()
            .get(id=ingestion_id)
        )
        job = HarJob.objects.select_for_update().select_related("trip").get(id=job_id)

        if ingestion.raw_status == TripIngestion.PhaseStatus.COMPLETED:
            result = {"skipped": "raw sensor ingestion already completed"}
            job.status = HarJob.Status.SUCCESS
            job.result = result
            job.error = ""
            job.save(update_fields=["status", "result", "error", "updated_at"])
            return result
        if ingestion.raw_status not in RAW_CLAIMABLE_STATUSES:
            return _skip_result("raw sensor", ingestion.raw_status)

        trip = ingestion.trip or job.trip
        if trip is None:
            raise ValueError("Trip assente per HAR finale")

        now = timezone.now()
        ingestion.raw_status = TripIngestion.PhaseStatus.PROCESSING
        ingestion.started_processing_at = now
        ingestion.error_message = ""
        ingestion.save(
            update_fields=[
                "raw_status",
                "started_processing_at",
                "error_message",
                "updated_at",
            ]
        )
        job.status = HarJob.Status.STARTED
        job.error = ""
        job.save(update_fields=["status", "error", "updated_at"])
    _add_elapsed_ms(timings, "claim_ms", claim_start)

    try:
        raw_load_start = time.perf_counter()
        sensor_windows = load_raw_sensor_windows(ingestion, timings=timings)
        _add_elapsed_ms(timings, "raw_load_total_ms", raw_load_start)
        with transaction.atomic():
            result = run_har_pipeline_with_timings(
                trip,
                sensor_windows=sensor_windows,
                timings=timings,
            )
            success_update_start = time.perf_counter()
            ingestion.raw_status = TripIngestion.PhaseStatus.COMPLETED
            ingestion.error_message = ""
            ingestion.completed_at = timezone.now()
            ingestion.failed_at = None
            ingestion.save(
                update_fields=[
                    "raw_status",
                    "error_message",
                    "completed_at",
                    "failed_at",
                    "updated_at",
                ]
            )
            job.status = HarJob.Status.SUCCESS
            job.result = result
            job.error = ""
            job.save(update_fields=["status", "result", "error", "updated_at"])
            _after_har_success(trip)
            _add_elapsed_ms(timings, "success_update_ms", success_update_start)
        _add_elapsed_ms(timings, "total_ms", total_start)
        _log_har_timing(
            ingestion_id=ingestion.id,
            job_id=job.id,
            trip_id=trip.id,
            timings=timings,
            result=result,
        )
    except InvalidRawSensorPayload as exc:
        ingestion.raw_status = TripIngestion.PhaseStatus.FAILED_FINAL
        ingestion.error_message = str(exc)
        ingestion.failed_at = timezone.now()
        ingestion.save(
            update_fields=["raw_status", "error_message", "failed_at", "updated_at"]
        )
        job.status = HarJob.Status.FAILURE
        job.error = str(exc)
        job.save(update_fields=["status", "error", "updated_at"])
        publish_diary_status_on_commit(
            trip.id,
            DIARY_STATUS_FAILED,
            reason=DIARY_ENRICHMENT_FAILED_REASON,
        )
        raise
    except Exception as exc:  # noqa: BLE001
        will_retry = self.request.retries < self.max_retries
        ingestion.raw_status = (
            TripIngestion.PhaseStatus.FAILED_RETRYABLE
            if will_retry
            else TripIngestion.PhaseStatus.FAILED_FINAL
        )
        ingestion.error_message = str(exc)
        ingestion.failed_at = timezone.now()
        ingestion.save(
            update_fields=["raw_status", "error_message", "failed_at", "updated_at"]
        )
        job.status = HarJob.Status.FAILURE
        job.error = str(exc)
        job.save(update_fields=["status", "error", "updated_at"])
        if not will_retry:
            publish_diary_status_on_commit(
                trip.id,
                DIARY_STATUS_FAILED,
                reason=DIARY_ENRICHMENT_FAILED_REASON,
            )
        if will_retry:
            raise self.retry(exc=exc)
        raise

    return result
