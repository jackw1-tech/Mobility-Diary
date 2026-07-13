import logging
from time import perf_counter

from celery import shared_task
from django.db import transaction
from django.utils import timezone

from .ingestion.raw_sensor_loader import load_raw_sensor_windows_with_metrics
from .models import (
    HarJob,
    PlaceMiningStatus,
    TripIngestion,
)
from .ml.pipeline import run_pipeline
from .services.sensor_readings import persist_raw_sensor_readings
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


def _place_mining_status_for_update(user_id: int) -> PlaceMiningStatus:
    status, _ = PlaceMiningStatus.objects.get_or_create(
        user_id=user_id,
        defaults={
            "status": PlaceMiningStatus.Status.IDLE,
            "requested_at": timezone.now(),
        },
    )
    return PlaceMiningStatus.objects.select_for_update().get(pk=status.pk)


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


@shared_task(bind=True, max_retries=3, default_retry_delay=30)
def process_trip_har_final(self, job_id: int, ingestion_id: int) -> dict:
    task_started = perf_counter()
    phase_timings_ms: dict[str, float] = {}
    raw_load_timings_ms: dict[str, float] = {}
    pipeline_timings_ms: dict[str, float] = {}
    sensor_windows_count = 0
    raw_part_count = 0
    compressed_bytes = 0
    decompressed_bytes = 0
    persisted_readings = 0
    trip_id = None

    status_started = perf_counter()
    with transaction.atomic():
        ingestion = (
            TripIngestion.objects.select_for_update()
            .get(id=ingestion_id)
        )
        job = HarJob.objects.select_for_update().select_related("trip").get(id=job_id)
        trip = ingestion.trip or job.trip
        trip_id = trip.id

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
    phase_timings_ms["mark_processing"] = _elapsed_ms(status_started)

    try:
        raw_load_started = perf_counter()
        raw_load = load_raw_sensor_windows_with_metrics(ingestion)
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

            finalize_started = perf_counter()
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
        phase_timings_ms["mark_completed"] = _elapsed_ms(finalize_started)
    except Exception as exc:
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
        phase_timings_ms["task_total_until_error"] = _elapsed_ms(task_started)
        _log_har_phase2_timing(
            "failed",
            ingestion_id=ingestion_id,
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

    raw_persist_started = perf_counter()
    try:
        persisted_readings = persist_raw_sensor_readings(trip, sensor_windows)
    except Exception:
        persisted_readings = 0
    phase_timings_ms["raw_sensor_reading_insert_after_completion"] = _elapsed_ms(
        raw_persist_started
    )
    result["raw_readings_persisted"] = persisted_readings
    try:
        job.result = result
        job.save(update_fields=["result", "updated_at"])
    except Exception:
        pass

    if _request_place_mining(trip.user_id):
        _schedule_place_mining(trip.user_id)

    phase_timings_ms["task_total"] = _elapsed_ms(task_started)
    _log_har_phase2_timing(
        "completed",
        ingestion_id=ingestion_id,
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
    ingestion_id: int,
    trip_id: int | None,
    job_id: int,
    phase_timings_ms: dict[str, float],
    raw_load_timings_ms: dict[str, float],
    pipeline_timings_ms: dict[str, float],
    raw_part_count: int,
    sensor_windows_count: int,
    persisted_readings: int,
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
        "ingestion_id": ingestion_id,
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


def _rounded(values: dict[str, float]) -> dict[str, float]:
    return {key: round(value, 2) for key, value in values.items()}


def _percentages(values: dict[str, float], total_ms: float) -> dict[str, float]:
    return {key: _percentage(value, total_ms) for key, value in values.items()}


def _percentage(value: float, total_ms: float) -> float:
    if total_ms <= 0:
        return 0.0
    return round((value / total_ms) * 100, 2)
