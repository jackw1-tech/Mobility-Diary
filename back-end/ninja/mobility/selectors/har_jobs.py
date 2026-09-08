"""Repository dell'HarJob.

Unico punto del progetto in cui compare `HarJob.objects`.
"""

from __future__ import annotations

from django.db import transaction

from ..models import HarJob


def create_har_job(trip_id: int) -> HarJob:
    return HarJob.objects.create(trip_id=trip_id)


def locked_har_job_for_processing(job_id: int) -> HarJob:
    return HarJob.objects.select_for_update().select_related("trip").get(id=job_id)


def har_job_for_raw_persistence(job_id: int) -> HarJob:
    return HarJob.objects.select_related("trip").get(id=job_id)


def merge_har_job_result(job_id: int, updates: dict) -> dict:
    with transaction.atomic():
        job = HarJob.objects.select_for_update().get(id=job_id)
        result = job.result if isinstance(job.result, dict) else {}
        result = {**result, **updates}
        job.result = result
        job.save(update_fields=["result", "updated_at"])
        return result
