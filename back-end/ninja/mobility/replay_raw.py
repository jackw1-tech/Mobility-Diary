"""Rigenerazione bucket-to-bucket dell'Evidenza Sensoriale Grezza.

Condiviso da Ricaricamento Diretto (`reload_trip`) e Riproduzione Live
(`create_core_inline`): legge le sensor window sorgente, le shifta nel tempo e,
con un cutoff opzionale, scarta quelle iniziate dopo lo Stop. Scrive nuovi
oggetti sotto il prefisso dell'upload e accoda l'HAR finale.
"""

from __future__ import annotations

import gzip
import hashlib
import json
from datetime import datetime, timedelta
from datetime import timezone as dt_timezone

from django.db import transaction
from django.utils import timezone
from django.utils.dateparse import parse_datetime

from shared.exceptions import ServiceError

from .upload import selectors as upload_selectors
from .upload import storage
from .upload.raw_sensor_codec import (
    InvalidRawSensorPayload,
    decode_sensor_windows_payload,
)
from .models import Trip, TripUpload
from .replay_windows_cache import cache_windows, get_cached_windows
from .selectors import har_jobs as har_jobs_repository
from .tasks import process_trip_har_final


class ReplayRawError(ServiceError):
    """Errore di dominio della rigenerazione raw, indipendente dal chiamante.

    E' un modulo di dominio (non un service ne' un router): non deve
    sollevare `ninja.errors.HttpError` direttamente. I due service che lo
    invocano (`mobility.services.reload`, `mobility.upload.services`)
    catturano questa eccezione e la ritraducono nel proprio errore di
    dominio, cosi' il router continua a vedere solo `ReloadServiceError` /
    `UploadServiceError` come prima.
    """

    status_code = 409


class ReplayStorageUnavailable(ReplayRawError):
    status_code = 503

_START_FIELD = "window_start"
_END_FIELD = "window_end"
_DECODE_ERRORS = (
    KeyError,
    gzip.BadGzipFile,
    EOFError,
    UnicodeDecodeError,
    InvalidRawSensorPayload,
    json.JSONDecodeError,
    TypeError,
    ValueError,
)


def _window_field(window: dict, field: str) -> datetime:
    if field not in window:
        raise ValueError(f"timestamp raw mancante: {field}")
    parsed = parse_datetime(str(window[field]))
    if parsed is None:
        raise ValueError(f"timestamp raw non valido: {field}")
    if timezone.is_naive(parsed):
        parsed = timezone.make_aware(parsed, dt_timezone.utc)
    return parsed


def _shift_field(window: dict, field: str, shift) -> None:
    # I microsecondi vanno preservati: le finestre sono lunghe 5 s e la
    # pipeline HAR le ordina e le allinea sui timestamp: troncarli al secondo
    # farebbe collassare finestre distinte sullo stesso istante.
    shifted = _window_field(window, field) + shift
    window[field] = (
        shifted.astimezone(dt_timezone.utc).isoformat().replace("+00:00", "Z")
    )


def _shifted_part_body(object_key: str, shift, cutoff) -> bytes | None:
    raw = gzip.decompress(storage.read_object(object_key))
    payload = json.loads(raw.decode("utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("payload raw sensor senza oggetto radice")
    windows = payload.get("windows")
    if not isinstance(windows, list):
        raise ValueError("payload raw sensor senza lista windows")

    kept = []
    for window in windows:
        if not isinstance(window, dict):
            raise ValueError("sensor window non valida")
        if cutoff is not None and _window_field(window, _START_FIELD) > cutoff:
            continue
        _shift_field(window, _START_FIELD, shift)
        _shift_field(window, _END_FIELD, shift)
        kept.append(window)

    if not kept:
        return None
    payload["windows"] = kept
    return gzip.compress(json.dumps(payload).encode("utf-8"))


""" 
Dato il trip e l'offset calcolato come durata * velocità
Recupera tutte le TripUploadPart
Per oguna di esse scarica i dati dei sensori e i dati aggiuntivi se non sono già in cache
Usa start_us e end_us per trovare la 500 x 6 giusta
"""
def source_sensor_window_at(
    source: Trip, offset_seconds: int
) -> list[list[float]] | None:
    windows = get_cached_windows(source.id)
    if windows is None:
        parts = upload_selectors.completed_raw_parts_for_trip(source)
        windows = []
        for part in parts:
            try:
                raw = gzip.decompress(storage.read_object(part.object_key))
                windows.extend(decode_sensor_windows_payload(raw))
            except _DECODE_ERRORS:
                continue
        cache_windows(source.id, windows)
    if not windows:
        return None

    base = source.started_at or windows[0].start_timestamp
    target = base + timedelta(seconds=offset_seconds)
    for window in windows:
        if window.start_timestamp <= target < window.end_timestamp:
            if window.matrix is None:
                return None
            return [
                [float(value) for value in row[:6]]
                for row in window.matrix
            ]
    return None


def regenerate_raw_and_queue_har(
    upload: TripUpload,
    source: Trip,
    *,
    shift,
    now,
    cutoff: datetime | None = None,
) -> None:
    """Rigenera i raw sorgente nell'upload e accoda l'HAR. Rigetta con 409 se
    le telemetrie sorgenti mancano/illeggibili, con 503 se lo storage fallisce."""
    parts = upload_selectors.completed_raw_parts_for_trip(source)
    if not parts.exists():
        raise ReplayRawError("telemetrie sorgente non disponibili")
    try:
        shifted_parts = [
            shifted
            for part in parts
            if (
                shifted := _shifted_part_body(part.object_key, shift, cutoff)
            ) is not None
        ]
    except _DECODE_ERRORS as exc:
        raise ReplayRawError("telemetrie sorgente non disponibili") from exc
    if not shifted_parts:
        raise ReplayRawError("telemetrie sorgente non disponibili")

    written: list[str] = []
    try:
        for sequence, body in enumerate(shifted_parts, start=1):
            object_key = storage.raw_part_object_key(
                upload.raw_base_path, sequence
            )
            sha256 = hashlib.sha256(body).hexdigest()
            try:
                storage.write_object(object_key, body, sha256=sha256)
            except Exception as exc:
                raise ReplayStorageUnavailable("storage ricaricamento non disponibile") from exc
            written.append(object_key)
            upload_selectors.create_upload_part(
                upload,
                sequence=sequence,
                sha256=sha256,
                object_key=object_key,
                received_at=now,
            )
        upload.expected_raw_parts = len(shifted_parts)
        upload.raw_status = TripUpload.PhaseStatus.QUEUED
        upload.queued_at = now
        upload.save(
            update_fields=["expected_raw_parts", "raw_status", "queued_at", "updated_at"]
        )
        job = har_jobs_repository.create_har_job(upload.trip_id)
        transaction.on_commit(lambda: process_trip_har_final.delay(job.id, upload.id))
    except Exception:
        for object_key in written:
            try:
                storage.delete_object(object_key)
            except Exception:
                pass
        raise
