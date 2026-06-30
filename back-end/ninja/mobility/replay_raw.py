"""Rigenerazione bucket-to-bucket dell'Evidenza Sensoriale Grezza.

Condiviso da Ricaricamento Diretto (`reload_trip`) e Riproduzione Live
(`create_core_inline`): legge le sensor window sorgente, le shifta nel tempo e,
con un cutoff opzionale, scarta quelle iniziate dopo lo Stop. Scrive nuovi
oggetti sotto il prefisso dell'ingestion e accoda l'HAR finale.
"""

from __future__ import annotations

import gzip
import hashlib
import json
from datetime import datetime
from datetime import timezone as dt_timezone

from django.db import transaction
from django.utils import timezone
from django.utils.dateparse import parse_datetime
from ninja.errors import HttpError

from .ingestion import storage
from .models import HarJob, PartKind, Trip, TripIngestion, TripIngestionPart

_START_FIELDS = ("window_start", "start")
_END_FIELDS = ("window_end", "end")
_DECODE_ERRORS = (
    KeyError,
    gzip.BadGzipFile,
    EOFError,
    UnicodeDecodeError,
    json.JSONDecodeError,
    TypeError,
    ValueError,
)


def _window_field(window: dict, names: tuple[str, str]) -> datetime:
    for field in names:
        if field in window:
            parsed = parse_datetime(str(window[field]))
            if parsed is None:
                raise ValueError(f"timestamp raw non valido: {field}")
            if timezone.is_naive(parsed):
                parsed = timezone.make_aware(parsed, dt_timezone.utc)
            return parsed
    raise ValueError(f"timestamp raw mancante: {names[0]}")


def _shift_field(window: dict, names: tuple[str, str], shift) -> None:
    for field in names:
        if field in window:
            shifted = _window_field(window, names) + shift
            window[field] = (
                shifted.astimezone(dt_timezone.utc)
                .replace(microsecond=0)
                .isoformat()
                .replace("+00:00", "Z")
            )
            return


def _shifted_part_body(object_key: str, shift, cutoff) -> bytes | None:
    payload = json.loads(gzip.decompress(storage.read_object(object_key)).decode("utf-8"))
    windows = payload.get("windows") if isinstance(payload, dict) else payload
    if not isinstance(windows, list):
        raise ValueError("payload raw sensor senza lista windows")
    kept = []
    for window in windows:
        if not isinstance(window, dict):
            raise ValueError("sensor window non valida")
        if cutoff is not None and _window_field(window, _START_FIELDS) > cutoff:
            continue
        _shift_field(window, _START_FIELDS, shift)
        _shift_field(window, _END_FIELDS, shift)
        kept.append(window)
    if not kept:
        return None
    if isinstance(payload, dict):
        payload["windows"] = kept
    else:
        payload = kept
    return gzip.compress(json.dumps(payload).encode("utf-8"))


def regenerate_raw_and_queue_har(
    ingestion: TripIngestion,
    source: Trip,
    *,
    shift,
    now,
    cutoff: datetime | None = None,
) -> None:
    """Rigenera i raw sorgente nell'ingestion e accoda l'HAR. Rigetta con 409 se
    le telemetrie sorgenti mancano/illeggibili, con 503 se lo storage fallisce."""
    source_ingestion = TripIngestion.objects.filter(
        trip=source,
        raw_status=TripIngestion.PhaseStatus.COMPLETED,
    ).order_by("-updated_at").first()

    if not source_ingestion:
        raise HttpError(409, "telemetrie sorgente non disponibili")

    parts = TripIngestionPart.objects.filter(
        ingestion=source_ingestion,
        kind=PartKind.SENSOR_WINDOWS,
        received_at__isnull=False,
    ).order_by("sequence")
    try:
        bodies = [
            body
            for part in parts
            if (body := _shifted_part_body(part.object_key, shift, cutoff)) is not None
        ]
    except _DECODE_ERRORS as exc:
        raise HttpError(409, "telemetrie sorgente non disponibili") from exc
    if not bodies:
        raise HttpError(409, "telemetrie sorgente non disponibili")

    written: list[str] = []
    try:
        for sequence, body in enumerate(bodies, start=1):
            object_key = f"{ingestion.raw_base_path}sensor_windows_{sequence:04d}.json.gz"
            sha256 = hashlib.sha256(body).hexdigest()
            try:
                storage.write_object(object_key, body, sha256=sha256)
            except Exception as exc:
                raise HttpError(503, "storage ricaricamento non disponibile") from exc
            written.append(object_key)
            TripIngestionPart.objects.create(
                ingestion=ingestion,
                kind=PartKind.SENSOR_WINDOWS,
                sequence=sequence,
                sha256=sha256,
                size_bytes=len(body),
                object_key=object_key,
                received_at=now,
            )
        ingestion.expected_raw_parts = {PartKind.SENSOR_WINDOWS: len(bodies)}
        ingestion.raw_status = TripIngestion.PhaseStatus.QUEUED
        ingestion.queued_at = now
        ingestion.save(
            update_fields=["expected_raw_parts", "raw_status", "queued_at", "updated_at"]
        )
        job = HarJob.objects.create(trip=ingestion.trip, kind=HarJob.Kind.FINAL_TRIP)
        from .tasks import process_trip_har_final

        transaction.on_commit(lambda: process_trip_har_final.delay(job.id, ingestion.id))
    except Exception:
        for object_key in written:
            try:
                storage.delete_object(object_key)
            except Exception:
                pass
        raise
