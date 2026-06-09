from celery import shared_task

from .models import HarJob


@shared_task(bind=True)
def process_trip_har(self, job_id: int) -> dict:
    job = HarJob.objects.get(id=job_id)
    job.status = HarJob.Status.STARTED
    job.save(update_fields=["status", "updated_at"])

    window_count = job.trip.sensor_windows.count()
    result = {
        "window_count": window_count,
        "message": "HAR worker placeholder completed",
    }

    job.status = HarJob.Status.SUCCESS
    job.result = result
    job.save(update_fields=["status", "result", "updated_at"])
    return result

