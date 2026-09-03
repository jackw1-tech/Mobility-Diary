import logging
from time import perf_counter

from celery import shared_task
from celery.signals import worker_process_init
from django.db import transaction
from django.utils import timezone

from .upload import selectors as upload_repository
from .upload.raw_sensor_loader import load_raw_sensor_windows_with_metrics
from .models import (
    HarJob,
    PlaceMiningStatus,
    TripUpload,
)
from .ml.har_adapter import HarModelUnavailable, warm_har_model
from .ml.pipeline import run_pipeline
from .private_diary_cache import cache_diary, get_places_version
from .selectors import har_jobs as har_jobs_repository
from .services.diary_view import build_private_diary
from .selectors import place_mining_status as place_mining_status_repository
from .selectors.sensor_readings import replace_raw_sensor_readings
from .significant_places import mine_user_significant_places

logger = logging.getLogger(__name__)


_PLACE_MINING_PENDING_FIELDS = [
    "status",
    "requested_at",
    "started_at",
    "finished_at",
    "error_message",
    "rerun_requested",
]


@worker_process_init.connect
def warm_har_model_on_worker_start(**_kwargs) -> None:
    started = perf_counter()
    try:
        warm_har_model()
    except HarModelUnavailable:
        logger.exception("Warmup modello HAR non riuscito")
        return
    logger.info(
        "Warmup modello HAR completato in %.2f ms",
        _elapsed_ms(started),
    )


def _place_mining_status_for_update(user_id: int) -> PlaceMiningStatus:
    return place_mining_status_repository.locked_status_for_user(
        user_id,
        default_status=PlaceMiningStatus.Status.IDLE,
        requested_at=timezone.now(),
    )


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
    status.save(update_fields=[*_PLACE_MINING_PENDING_FIELDS, "updated_at"])


def _request_place_mining(user_id: int) -> bool:
    with transaction.atomic():
        status = _place_mining_status_for_update(user_id)
        now = timezone.now()
        if status.status in {
            PlaceMiningStatus.Status.PENDING,
            PlaceMiningStatus.Status.RUNNING,
        }:
            status.requested_at = now
            status.rerun_requested = True
            status.save(
                update_fields=["requested_at", "rerun_requested", "updated_at"]
            )
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
        status.save(
            update_fields=[
                "status",
                "started_at",
                "finished_at",
                "error_message",
                "updated_at",
            ]
        )
        return True


def _finish_place_mining_run(
    user_id: int,
    *,
    status_value: str,
    error_message: str = "",
) -> bool:
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
        status.save(
            update_fields=[
                "status",
                "finished_at",
                "error_message",
                "rerun_requested",
                "updated_at",
            ]
        )
        return False


@shared_task(bind=True, max_retries=3, retry_backoff=True)
def mine_significant_places(self, user_id: int) -> dict:
    if not _begin_place_mining_run(user_id):
        return {"skipped": "place mining not pending"}
    result = mine_user_significant_places(user_id)
    if _finish_place_mining_run(
        user_id,
        status_value=PlaceMiningStatus.Status.SUCCEEDED,
    ):
        _schedule_place_mining(user_id)
    return result


def _schedule_place_mining(user_id: int) -> None:
    transaction.on_commit(lambda: mine_significant_places.delay(user_id))


def _merge_har_job_result(job_id: int, updates: dict) -> dict:
    return har_jobs_repository.merge_har_job_result(job_id, updates)


@shared_task(bind=True, max_retries=3, retry_backoff=True, default_retry_delay=30)
def persist_trip_raw_sensor_readings(self, job_id: int, upload_id: int) -> dict:
    task_started = perf_counter()
    phase_timings_ms: dict[str, float] = {}
    raw_load_timings_ms: dict[str, float] = {}
    raw_part_count = 0
    sensor_windows_count = 0
    compressed_bytes = 0
    decompressed_bytes = 0
    trip_id = None

    try:
        lookup_started = perf_counter()
        upload = upload_repository.upload_with_trip(upload_id)
        job = har_jobs_repository.har_job_with_trip(job_id)
        trip = upload.trip or job.trip
        if trip is None:
            raise ValueError("trip non disponibile per la persistenza raw sensor")
        trip_id = trip.id
        phase_timings_ms["lookup_context"] = _elapsed_ms(lookup_started)

        raw_load_started = perf_counter()
        raw_load = load_raw_sensor_windows_with_metrics(upload)
        sensor_windows = raw_load.windows
        phase_timings_ms["raw_load_total"] = _elapsed_ms(raw_load_started)
        raw_load_timings_ms = raw_load.timings_ms
        raw_part_count = raw_load.part_count
        sensor_windows_count = len(sensor_windows)
        compressed_bytes = raw_load.compressed_bytes
        decompressed_bytes = raw_load.decompressed_bytes

        persist_started = perf_counter()
        persisted_readings = replace_raw_sensor_readings(trip, sensor_windows)
        phase_timings_ms["raw_sensor_reading_replace"] = _elapsed_ms(
            persist_started
        )
        phase_timings_ms["task_total"] = _elapsed_ms(task_started)

        _merge_har_job_result(
            job_id,
            {
                "raw_readings_persisted": persisted_readings,
                "raw_readings_persistence_status": "COMPLETED",
                "raw_readings_persistence_timings_ms": _rounded(phase_timings_ms),
            },
        )
        _log_raw_sensor_persistence_timing(
            "completed",
            upload_id=upload_id,
            trip_id=trip_id,
            job_id=job_id,
            phase_timings_ms=phase_timings_ms,
            raw_load_timings_ms=raw_load_timings_ms,
            raw_part_count=raw_part_count,
            sensor_windows_count=sensor_windows_count,
            persisted_readings=persisted_readings,
            compressed_bytes=compressed_bytes,
            decompressed_bytes=decompressed_bytes,
        )
        return {
            "trip_id": trip_id,
            "raw_readings_persisted": persisted_readings,
            "raw_readings_persistence_status": "COMPLETED",
        }
    except Exception as exc:
        will_retry = self.request.retries < self.max_retries
        phase_timings_ms["task_total_until_error"] = _elapsed_ms(task_started)
        _log_raw_sensor_persistence_timing(
            "failed_retryable" if will_retry else "failed_final",
            upload_id=upload_id,
            trip_id=trip_id,
            job_id=job_id,
            phase_timings_ms=phase_timings_ms,
            raw_load_timings_ms=raw_load_timings_ms,
            raw_part_count=raw_part_count,
            sensor_windows_count=sensor_windows_count,
            persisted_readings=None,
            compressed_bytes=compressed_bytes,
            decompressed_bytes=decompressed_bytes,
            error=str(exc),
        )
        if will_retry:
            raise self.retry(exc=exc)
        _merge_har_job_result(
            job_id,
            {
                "raw_readings_persisted": 0,
                "raw_readings_persistence_status": "FAILED",
                "raw_readings_persistence_error": str(exc),
            },
        )
        raise


@shared_task(bind=True, max_retries=3, default_retry_delay=30)
def process_trip_har_final(self, job_id: int, upload_id: int) -> dict:
    task_started = perf_counter()
    phase_timings_ms: dict[str, float] = {}
    raw_load_timings_ms: dict[str, float] = {}
    pipeline_timings_ms: dict[str, float] = {}
    sensor_windows_count = 0
    raw_part_count = 0
    compressed_bytes = 0
    decompressed_bytes = 0
    persisted_readings = None
    trip_id = None

    status_started = perf_counter()
    with transaction.atomic():
        upload = upload_repository.locked_upload_by_id(upload_id)
        job = har_jobs_repository.locked_har_job_with_trip(job_id)
        trip = upload.trip or job.trip
        trip_id = trip.id

        now = timezone.now()
        upload.raw_status = TripUpload.PhaseStatus.PROCESSING
        upload.started_processing_at = now
        upload.error_message = ""
        upload.save(
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
    phase_timings_ms["mark_processing"] = _elapsed_ms(status_started)

    try:
        raw_load_started = perf_counter()
        raw_load = load_raw_sensor_windows_with_metrics(upload)
        sensor_windows = raw_load.windows
        phase_timings_ms["raw_load_total"] = _elapsed_ms(raw_load_started)
        raw_load_timings_ms = raw_load.timings_ms
        sensor_windows_count = len(sensor_windows)
        raw_part_count = raw_load.part_count
        compressed_bytes = raw_load.compressed_bytes
        decompressed_bytes = raw_load.decompressed_bytes

        with transaction.atomic():
            pipeline_started = perf_counter()
            result = run_pipeline(
                trip,
                sensor_windows=sensor_windows,
            )
            phase_timings_ms["pipeline_total"] = _elapsed_ms(pipeline_started)
            pipeline_timings_ms = result.get("pipeline_timings_ms", {})
            result["raw_readings_persisted"] = None
            result["raw_readings_persistence_status"] = "QUEUED"

            finalize_started = perf_counter()
            upload.raw_status = TripUpload.PhaseStatus.COMPLETED
            upload.error_message = ""
            upload.completed_at = timezone.now()
            upload.failed_at = None
            upload.save(
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
        phase_timings_ms["mark_completed"] = _elapsed_ms(finalize_started)

        # Prewarm: calcola e cache il diario privato ora, fuori dal percorso
        # critico dell'utente, cosi' il primo click su questo viaggio trova
        # gia' la cache calda invece di pagare il calcolo al momento. Non
        # critico: un fallimento qui non deve far fallire l'upload.
        try:
            places_version = get_places_version(trip.user_id)
            cache_diary(trip.id, places_version, build_private_diary(trip))
        except Exception:
            logger.exception(
                "Prewarm diario privato fallito per trip_id=%s", trip.id
            )
    except Exception as exc:
        will_retry = self.request.retries < self.max_retries
        upload.raw_status = (
            TripUpload.PhaseStatus.FAILED_RETRYABLE
            if will_retry
            else TripUpload.PhaseStatus.FAILED_FINAL
        )
        upload.error_message = str(exc)
        upload.failed_at = timezone.now()
        upload.save(
            update_fields=["raw_status", "error_message", "failed_at", "updated_at"]
        )
        job.status = HarJob.Status.FAILURE
        job.error = str(exc)
        job.save(update_fields=["status", "error", "updated_at"])
        phase_timings_ms["task_total_until_error"] = _elapsed_ms(task_started)
        _log_har_phase2_timing(
            "failed",
            upload_id=upload_id,
            trip_id=trip_id,
            job_id=job_id,
            phase_timings_ms=phase_timings_ms,
            raw_load_timings_ms=raw_load_timings_ms,
            pipeline_timings_ms=pipeline_timings_ms,
            raw_part_count=raw_part_count,
            sensor_windows_count=sensor_windows_count,
            persisted_readings=persisted_readings,
            compressed_bytes=compressed_bytes,
            decompressed_bytes=decompressed_bytes,
            error=str(exc),
        )
        if will_retry:
            raise self.retry(exc=exc)
        raise

    raw_persist_enqueue_started = perf_counter()
    try:
        persist_trip_raw_sensor_readings.delay(job_id, upload_id)
    except Exception as exc:
        _merge_har_job_result(
            job_id,
            {
                "raw_readings_persisted": 0,
                "raw_readings_persistence_status": "FAILED",
                "raw_readings_persistence_error": str(exc),
            },
        )
        logger.exception(
            "Impossibile accodare la persistenza raw sensor "
            "per upload_id=%s job_id=%s",
            upload_id,
            job_id,
        )
    phase_timings_ms["raw_sensor_reading_enqueue"] = _elapsed_ms(
        raw_persist_enqueue_started
    )

    if _request_place_mining(trip.user_id):
        _schedule_place_mining(trip.user_id)

    phase_timings_ms["task_total"] = _elapsed_ms(task_started)
    _log_har_phase2_timing(
        "completed",
        upload_id=upload_id,
        trip_id=trip_id,
        job_id=job_id,
        phase_timings_ms=phase_timings_ms,
        raw_load_timings_ms=raw_load_timings_ms,
        pipeline_timings_ms=pipeline_timings_ms,
        raw_part_count=raw_part_count,
        sensor_windows_count=sensor_windows_count,
        persisted_readings=persisted_readings,
        compressed_bytes=compressed_bytes,
        decompressed_bytes=decompressed_bytes,
    )
    return result


def _elapsed_ms(started_at: float) -> float:
    return (perf_counter() - started_at) * 1000


def _log_har_phase2_timing(
    status: str,
    *,
    upload_id: int,
    trip_id: int | None,
    job_id: int,
    phase_timings_ms: dict[str, float],
    raw_load_timings_ms: dict[str, float],
    pipeline_timings_ms: dict[str, float],
    raw_part_count: int,
    sensor_windows_count: int,
    persisted_readings: int | None,
    compressed_bytes: int,
    decompressed_bytes: int,
    error: str | None = None,
) -> None:
    task_total_ms = phase_timings_ms.get("task_total")
    if task_total_ms is None:
        task_total_ms = phase_timings_ms.get("task_total_until_error")
    total_ms = task_total_ms or sum(
        value
        for key, value in phase_timings_ms.items()
        if not key.startswith("task_total")
    )

    phase_percentages = _percentages(phase_timings_ms, total_ms)
    raw_load_percentages = _percentages(raw_load_timings_ms, total_ms)
    pipeline_percentages = _percentages(pipeline_timings_ms, total_ms)
    measured_ms = sum(
        value
        for key, value in phase_timings_ms.items()
        if not key.startswith("task_total")
    )
    overhead_ms = max(total_ms - measured_ms, 0.0)
    overhead_pct = _percentage(overhead_ms, total_ms)

    log_payload = {
        "status": status,
        "upload_id": upload_id,
        "trip_id": trip_id,
        "job_id": job_id,
        "total_ms": round(total_ms, 2),
        "phases_ms": _rounded(phase_timings_ms),
        "phases_pct": phase_percentages,
        "raw_load_ms": _rounded(raw_load_timings_ms),
        "raw_load_pct_of_total": raw_load_percentages,
        "pipeline_ms": _rounded(pipeline_timings_ms),
        "pipeline_pct_of_total": pipeline_percentages,
        "unmeasured_overhead_ms": round(overhead_ms, 2),
        "unmeasured_overhead_pct": overhead_pct,
        "raw_parts": raw_part_count,
        "sensor_windows": sensor_windows_count,
        "raw_readings_persisted": persisted_readings,
        "compressed_bytes": compressed_bytes,
        "decompressed_bytes": decompressed_bytes,
    }
    if error:
        log_payload["error"] = error

    logger.info("[HAR-PHASE2-TIMING] %s", log_payload)


def _log_raw_sensor_persistence_timing(
    status: str,
    *,
    upload_id: int,
    trip_id: int | None,
    job_id: int,
    phase_timings_ms: dict[str, float],
    raw_load_timings_ms: dict[str, float],
    raw_part_count: int,
    sensor_windows_count: int,
    persisted_readings: int | None,
    compressed_bytes: int,
    decompressed_bytes: int,
    error: str | None = None,
) -> None:
    task_total_ms = phase_timings_ms.get("task_total")
    if task_total_ms is None:
        task_total_ms = phase_timings_ms.get("task_total_until_error")
    total_ms = task_total_ms or sum(
        value
        for key, value in phase_timings_ms.items()
        if not key.startswith("task_total")
    )

    log_payload = {
        "status": status,
        "upload_id": upload_id,
        "trip_id": trip_id,
        "job_id": job_id,
        "total_ms": round(total_ms, 2),
        "phases_ms": _rounded(phase_timings_ms),
        "phases_pct": _percentages(phase_timings_ms, total_ms),
        "raw_load_ms": _rounded(raw_load_timings_ms),
        "raw_load_pct_of_total": _percentages(raw_load_timings_ms, total_ms),
        "raw_parts": raw_part_count,
        "sensor_windows": sensor_windows_count,
        "raw_readings_persisted": persisted_readings,
        "compressed_bytes": compressed_bytes,
        "decompressed_bytes": decompressed_bytes,
    }
    if error:
        log_payload["error"] = error

    logger.info("[RAW-SENSOR-PERSIST-TIMING] %s", log_payload)


def _rounded(values: dict[str, float]) -> dict[str, float]:
    return {key: round(value, 2) for key, value in values.items()}


def _percentages(values: dict[str, float], total_ms: float) -> dict[str, float]:
    return {key: _percentage(value, total_ms) for key, value in values.items()}


def _percentage(value: float, total_ms: float) -> float:
    if total_ms <= 0:
        return 0.0
    return round((value / total_ms) * 100, 2)
