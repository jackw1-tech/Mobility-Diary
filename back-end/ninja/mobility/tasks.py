from celery import shared_task
from django.db import transaction
from django.utils import timezone

from .ingestion.raw_sensor_loader import load_raw_sensor_windows
from .models import (
    HarJob,
    PlaceMiningStatus,
    TripIngestion,
)
from .ml.pipeline import run_pipeline
from .services.sensor_readings import persist_raw_sensor_readings
from .significant_places import mine_user_significant_places


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
    with transaction.atomic():
        ingestion = (
            TripIngestion.objects.select_for_update()
            .get(id=ingestion_id)
        )
        job = HarJob.objects.select_for_update().select_related("trip").get(id=job_id)
        trip = ingestion.trip or job.trip

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

    try:
        sensor_windows = load_raw_sensor_windows(ingestion)
        persisted_readings = persist_raw_sensor_readings(trip, sensor_windows)
        with transaction.atomic():
            result = run_pipeline(
                trip,
                sensor_windows=sensor_windows,
            )
            result["raw_readings_persisted"] = persisted_readings
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
            if _request_place_mining(trip.user_id):
                _schedule_place_mining(trip.user_id)
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
        if will_retry:
            raise self.retry(exc=exc)
        raise

    return result
