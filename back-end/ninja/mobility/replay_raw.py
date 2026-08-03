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
import struct
from datetime import datetime, timedelta
from datetime import timezone as dt_timezone

from django.db import transaction
from django.utils import timezone
from django.utils.dateparse import parse_datetime
from ninja.errors import HttpError

from .ingestion import storage
from .ingestion.raw_sensor_codec import (
    InvalidRawSensorPayload,
    RawSensorPayloadFormat,
    _RAW_SENSOR_BINARY_HEADER,
    _RAW_SENSOR_BINARY_MAGIC,
    _RAW_SENSOR_BINARY_WINDOW_HEADER,
    decode_sensor_windows_payload,
    raw_sensor_payload_format,
)
from .models import HarJob, Trip, TripIngestion, TripIngestionPart

_START_FIELDS = ("window_start", "start")
_END_FIELDS = ("window_end", "end")
_UNIX_EPOCH = datetime(1970, 1, 1, tzinfo=dt_timezone.utc)
_DECODE_ERRORS = (
    KeyError,
    gzip.BadGzipFile,
    EOFError,
    UnicodeDecodeError,
    InvalidRawSensorPayload,
    json.JSONDecodeError,
    struct.error,
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


def _epoch_micros(value: datetime) -> int:
    if timezone.is_naive(value):
        value = timezone.make_aware(value, dt_timezone.utc)
    return _shift_micros(value.astimezone(dt_timezone.utc) - _UNIX_EPOCH)


def _shift_micros(shift: timedelta) -> int:
    return (
        shift.days * 24 * 60 * 60 * 1_000_000
        + shift.seconds * 1_000_000
        + shift.microseconds
    )


def _shifted_part_body(object_key: str, shift, cutoff) -> tuple[bytes, str] | None:
    raw = gzip.decompress(storage.read_object(object_key))
    if raw_sensor_payload_format(raw) == RawSensorPayloadFormat.BINARY:
        return _shifted_binary_part_body(raw, shift, cutoff)
    return _shifted_json_part_body(raw, shift, cutoff)


def _shifted_json_part_body(raw: bytes, shift, cutoff) -> tuple[bytes, str] | None:
    payload = json.loads(raw.decode("utf-8"))
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
    return gzip.compress(json.dumps(payload).encode("utf-8")), "json.gz"


def _shifted_binary_part_body(
    raw: bytes,
    shift,
    cutoff,
) -> tuple[bytes, str] | None:
    if len(raw) < _RAW_SENSOR_BINARY_HEADER.size:
        raise InvalidRawSensorPayload("payload raw sensor binario incompleto")

    magic, window_count = _RAW_SENSOR_BINARY_HEADER.unpack_from(raw, 0)
    if magic != _RAW_SENSOR_BINARY_MAGIC:
        raise InvalidRawSensorPayload("payload raw sensor binario non valido")

    cutoff_us = None if cutoff is None else _epoch_micros(cutoff)
    shift_us = _shift_micros(shift)
    cursor = _RAW_SENSOR_BINARY_HEADER.size
    kept = bytearray()
    kept_count = 0
    for _index in range(window_count):
        if cursor + _RAW_SENSOR_BINARY_WINDOW_HEADER.size > len(raw):
            raise InvalidRawSensorPayload("payload raw sensor binario troncato")
        (
            start_us,
            end_us,
            sample_rate,
            sample_count,
            channel_count,
        ) = _RAW_SENSOR_BINARY_WINDOW_HEADER.unpack_from(raw, cursor)
        cursor += _RAW_SENSOR_BINARY_WINDOW_HEADER.size

        if end_us <= start_us:
            raise InvalidRawSensorPayload(
                "sensor window con intervallo temporale non valido"
            )
        if sample_rate <= 0 or sample_count != 500 or channel_count != 6:
            raise InvalidRawSensorPayload("sensor window binaria non valida")

        value_bytes = sample_count * channel_count * 4
        if cursor + value_bytes > len(raw):
            raise InvalidRawSensorPayload("payload raw sensor binario troncato")
        matrix_bytes = raw[cursor : cursor + value_bytes]
        cursor += value_bytes

        if cutoff_us is not None and start_us > cutoff_us:
            continue

        kept.extend(
            _RAW_SENSOR_BINARY_WINDOW_HEADER.pack(
                start_us + shift_us,
                end_us + shift_us,
                sample_rate,
                sample_count,
                channel_count,
            )
        )
        kept.extend(matrix_bytes)
        kept_count += 1

    if cursor != len(raw):
        raise InvalidRawSensorPayload("payload raw sensor binario con byte extra")
    if kept_count == 0:
        return None

    payload = bytearray(
        _RAW_SENSOR_BINARY_HEADER.pack(
            _RAW_SENSOR_BINARY_MAGIC,
            kept_count,
        )
    )
    payload.extend(kept)
    return gzip.compress(bytes(payload)), "bin.gz"


def source_sensor_window_at(
    source: Trip, offset_seconds: int
) -> list[list[float]] | None:
    """Finestra sensori grezza (500x6, primi 6 canali) attiva a `offset_seconds`
    dall'inizio del viaggio sorgente. None se fuori range o telemetrie assenti.

    Read-only: usato dalla classificazione live dell'assistente durante una
    Riproduzione Live, dove l'offset e' il tempo trascorso dall'avvio del replay.
    """
    parts = TripIngestionPart.objects.filter(
        ingestion__trip=source,
        ingestion__raw_status=TripIngestion.PhaseStatus.COMPLETED,
        received_at__isnull=False,
    ).order_by("sequence", "id")
    windows = []
    for part in parts:
        try:
            raw = gzip.decompress(storage.read_object(part.object_key))
            windows.extend(decode_sensor_windows_payload(raw))
        except _DECODE_ERRORS:
            continue
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
    ingestion: TripIngestion,
    source: Trip,
    *,
    shift,
    now,
    cutoff: datetime | None = None,
) -> None:
    """Rigenera i raw sorgente nell'ingestion e accoda l'HAR. Rigetta con 409 se
    le telemetrie sorgenti mancano/illeggibili, con 503 se lo storage fallisce."""
    parts = TripIngestionPart.objects.filter(
        ingestion__trip=source,
        ingestion__raw_status=TripIngestion.PhaseStatus.COMPLETED,
        received_at__isnull=False,
    ).order_by("sequence", "id")
    if not parts.exists():
        raise HttpError(409, "telemetrie sorgente non disponibili")
    try:
        shifted_parts = [
            shifted
            for part in parts
            if (
                shifted := _shifted_part_body(part.object_key, shift, cutoff)
            ) is not None
        ]
    except _DECODE_ERRORS as exc:
        raise HttpError(409, "telemetrie sorgente non disponibili") from exc
    if not shifted_parts:
        raise HttpError(409, "telemetrie sorgente non disponibili")

    written: list[str] = []
    try:
        for sequence, (body, extension) in enumerate(shifted_parts, start=1):
            object_key = (
                f"{ingestion.raw_base_path}"
                f"sensor_windows_part_{sequence:04d}.{extension}"
            )
            sha256 = hashlib.sha256(body).hexdigest()
            try:
                storage.write_object(object_key, body, sha256=sha256)
            except Exception as exc:
                raise HttpError(503, "storage ricaricamento non disponibile") from exc
            written.append(object_key)
            TripIngestionPart.objects.create(
                ingestion=ingestion,
                sequence=sequence,
                sha256=sha256,
                size_bytes=len(body),
                object_key=object_key,
                received_at=now,
            )
        ingestion.expected_raw_parts = len(shifted_parts)
        ingestion.raw_status = TripIngestion.PhaseStatus.QUEUED
        ingestion.queued_at = now
        ingestion.save(
            update_fields=["expected_raw_parts", "raw_status", "queued_at", "updated_at"]
        )
        job = HarJob.objects.create(trip=ingestion.trip)
        from .tasks import process_trip_har_final

        transaction.on_commit(lambda: process_trip_har_final.delay(job.id, ingestion.id))
    except Exception:
        for object_key in written:
            try:
                storage.delete_object(object_key)
            except Exception:
                pass
        raise
