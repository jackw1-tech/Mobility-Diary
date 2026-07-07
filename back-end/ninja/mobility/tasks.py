import gzip
import inspect
import json
import logging
import struct
import time
from datetime import datetime, timezone as dt_timezone
from typing import Any

import numpy as np
from celery import shared_task
from django.contrib.gis.db.models.functions import Length
from django.contrib.gis.geos import LineString, Point
from django.db import transaction
from django.utils import timezone
from django.utils.dateparse import parse_datetime

from .diary_events import (
    DIARY_ENRICHMENT_FAILED_REASON,
    DIARY_STATUS_ENRICHED,
    DIARY_STATUS_FAILED,
    publish_diary_status_on_commit,
)
from .ingestion import storage
from .models import (
    GpsPoint,
    HarJob,
    PartKind,
    PlaceMiningStatus,
    StateTransition,
    Trip,
    TripIngestion,
)
from .ml.pipeline import PipelineSensorWindow, run_pipeline
from .significant_places import mine_user_significant_places

try:
    import orjson
except ModuleNotFoundError:  # pragma: no cover - fallback per ambienti non rebuildati
    orjson = None

logger = logging.getLogger(__name__)


class InvalidRawSensorPayload(ValueError):
    """Il blob raw e leggibile dallo storage ma non rispetta il contratto HAR."""


CORE_CLAIMABLE_STATUSES = {
    TripIngestion.PhaseStatus.PENDING,
    TripIngestion.PhaseStatus.RECEIVED,
    TripIngestion.PhaseStatus.QUEUED,
    TripIngestion.PhaseStatus.FAILED_RETRYABLE,
}
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
_RAW_SENSOR_BINARY_MAGIC = b"MDHARW1\x00"
_RAW_SENSOR_BINARY_HEADER = struct.Struct("<8sI")
_RAW_SENSOR_BINARY_WINDOW_HEADER = struct.Struct("<qqIII")


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


def _run_pipeline_with_timings(
    trip: Trip,
    *,
    sensor_windows: list[PipelineSensorWindow],
    timings: dict[str, Any],
) -> dict:
    try:
        parameters = inspect.signature(run_pipeline).parameters
    except (TypeError, ValueError):
        parameters = {}
    if "timings" in parameters:
        return run_pipeline(
            trip,
            sensor_windows=sensor_windows,
            timings=timings,
        )

    pipeline_start = time.perf_counter()
    result = run_pipeline(trip, sensor_windows=sensor_windows)
    _add_elapsed_ms(timings, "pipeline_total_ms", pipeline_start)
    return result


def _load_json_bytes(raw: bytes) -> Any:
    if orjson is not None:
        return orjson.loads(raw)
    return json.loads(raw.decode("utf-8"))


def _datetime_from_epoch_micros(value: int, field: str) -> datetime:
    try:
        seconds, micros = divmod(int(value), 1_000_000)
        return datetime.fromtimestamp(seconds, tz=dt_timezone.utc).replace(
            microsecond=micros
        )
    except (OSError, OverflowError, ValueError) as exc:
        raise InvalidRawSensorPayload(f"timestamp raw non valido: {field}") from exc


def _read_gzip_object(object_key: str, timings: dict[str, Any] | None = None) -> bytes:
    read_start = time.perf_counter()
    raw = storage.read_object(object_key)
    _add_elapsed_ms(timings, "raw_s3_read_ms", read_start)
    try:
        gzip_start = time.perf_counter()
        decompressed = gzip.decompress(raw)
        _add_elapsed_ms(timings, "raw_gzip_ms", gzip_start)
        return decompressed
    except (gzip.BadGzipFile, EOFError) as exc:
        raise InvalidRawSensorPayload("payload raw sensor gzip non valido") from exc


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


def _load_json_gz(object_key: str, timings: dict[str, Any] | None = None) -> dict:
    """Scarica e decomprime un blob .json.gz dallo storage."""
    decompressed = _read_gzip_object(object_key, timings=timings)
    try:
        json_start = time.perf_counter()
        payload = _load_json_bytes(decompressed)
        _add_elapsed_ms(timings, "raw_json_ms", json_start)
        return payload
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise InvalidRawSensorPayload("payload raw sensor JSON non valido") from exc


def _decode_binary_sensor_windows(raw: bytes) -> list[PipelineSensorWindow]:
    if len(raw) < _RAW_SENSOR_BINARY_HEADER.size:
        raise InvalidRawSensorPayload("payload raw sensor binario incompleto")

    magic, window_count = _RAW_SENSOR_BINARY_HEADER.unpack_from(raw, 0)
    if magic != _RAW_SENSOR_BINARY_MAGIC:
        raise InvalidRawSensorPayload("payload raw sensor binario non valido")

    cursor = _RAW_SENSOR_BINARY_HEADER.size
    windows: list[PipelineSensorWindow] = []
    try:
        for _index in range(window_count):
            if cursor + _RAW_SENSOR_BINARY_WINDOW_HEADER.size > len(raw):
                raise InvalidRawSensorPayload(
                    "payload raw sensor binario troncato"
                )
            (
                start_us,
                end_us,
                sample_rate,
                sample_count,
                channel_count,
            ) = _RAW_SENSOR_BINARY_WINDOW_HEADER.unpack_from(raw, cursor)
            cursor += _RAW_SENSOR_BINARY_WINDOW_HEADER.size

            start = _datetime_from_epoch_micros(start_us, "window_start")
            end = _datetime_from_epoch_micros(end_us, "window_end")
            if end <= start:
                raise InvalidRawSensorPayload(
                    "sensor window con intervallo temporale non valido"
                )
            if sample_rate <= 0:
                raise InvalidRawSensorPayload(
                    "sensor window con sample_rate_hz non valido"
                )
            if sample_count != 500:
                raise InvalidRawSensorPayload(
                    "sensor window con sample_count diverso da 500"
                )
            if channel_count != 6:
                raise InvalidRawSensorPayload(
                    "sensor window con channel_count diverso da 6"
                )

            value_count = sample_count * channel_count
            value_bytes = value_count * np.dtype("<f4").itemsize
            if cursor + value_bytes > len(raw):
                raise InvalidRawSensorPayload(
                    "payload raw sensor binario troncato"
                )
            matrix = np.frombuffer(
                raw,
                dtype="<f4",
                count=value_count,
                offset=cursor,
            ).reshape((sample_count, channel_count))
            cursor += value_bytes
            windows.append(
                PipelineSensorWindow(
                    start_timestamp=start,
                    end_timestamp=end,
                    sample_count=sample_count,
                    frequency_hz=sample_rate,
                    matrix=matrix,
                )
            )
    except (struct.error, ValueError) as exc:
        raise InvalidRawSensorPayload(
            "payload raw sensor binario non valido"
        ) from exc

    if cursor != len(raw):
        raise InvalidRawSensorPayload(
            "payload raw sensor binario con byte extra"
        )
    return windows


def _load_raw_sensor_part_windows(
    object_key: str,
    timings: dict[str, Any] | None = None,
) -> list[PipelineSensorWindow]:
    decompressed = _read_gzip_object(object_key, timings=timings)

    if decompressed.startswith(_RAW_SENSOR_BINARY_MAGIC):
        decode_start = time.perf_counter()
        windows = _decode_binary_sensor_windows(decompressed)
        _add_elapsed_ms(timings, "raw_binary_decode_ms", decode_start)
        return windows

    try:
        json_start = time.perf_counter()
        payload = _load_json_bytes(decompressed)
        _add_elapsed_ms(timings, "raw_json_ms", json_start)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise InvalidRawSensorPayload("payload raw sensor JSON non valido") from exc

    raw_windows = payload.get("windows") if isinstance(payload, dict) else payload
    if not isinstance(raw_windows, list):
        raise InvalidRawSensorPayload("payload raw sensor senza lista windows")
    parse_start = time.perf_counter()
    windows = [_parse_sensor_window(raw_window) for raw_window in raw_windows]
    _add_elapsed_ms(timings, "raw_window_parse_ms", parse_start)
    return windows


def _parse_required_datetime(value: Any, field: str):
    parsed = parse_datetime(str(value)) if value else None
    if parsed is None:
        raise InvalidRawSensorPayload(f"timestamp raw non valido: {field}")
    return parsed


def _window_matrix(raw_window: dict) -> list[list[float]]:
    matrix = raw_window.get("samples", raw_window.get("matrix"))
    if not isinstance(matrix, list) or not matrix:
        raise InvalidRawSensorPayload("sensor window senza matrice samples/matrix")
    normalized: list[list[float]] = []
    for row in matrix:
        if not isinstance(row, list) or len(row) < 6:
            raise InvalidRawSensorPayload("sensor window con riga matrice non valida")
        try:
            normalized.append([float(value) for value in row[:6]])
        except (TypeError, ValueError) as exc:
            raise InvalidRawSensorPayload(
                "sensor window con valore matrice non numerico"
            ) from exc
    return normalized


def _parse_sensor_window(raw_window: dict) -> PipelineSensorWindow:
    start = _parse_required_datetime(
        raw_window.get("window_start", raw_window.get("start")),
        "window_start",
    )
    end = _parse_required_datetime(
        raw_window.get("window_end", raw_window.get("end")),
        "window_end",
    )
    if end <= start:
        raise InvalidRawSensorPayload(
            "sensor window con intervallo temporale non valido"
        )

    try:
        sample_rate = int(
            raw_window.get("sample_rate_hz", raw_window.get("frequency_hz", 0))
        )
    except (TypeError, ValueError) as exc:
        raise InvalidRawSensorPayload(
            "sensor window con sample_rate_hz non valido"
        ) from exc
    if sample_rate <= 0:
        raise InvalidRawSensorPayload("sensor window con sample_rate_hz non valido")

    matrix = _window_matrix(raw_window)
    try:
        sample_count = int(raw_window.get("sample_count", len(matrix)))
    except (TypeError, ValueError) as exc:
        raise InvalidRawSensorPayload(
            "sensor window con sample_count non valido"
        ) from exc
    if sample_count != len(matrix):
        raise InvalidRawSensorPayload("sensor window con sample_count incoerente")
    if sample_count != 500:
        raise InvalidRawSensorPayload("sensor window con sample_count diverso da 500")

    return PipelineSensorWindow(
        start_timestamp=start,
        end_timestamp=end,
        sample_count=sample_count,
        frequency_hz=sample_rate,
        matrix=matrix,
    )


def _load_raw_sensor_windows(
    ingestion: TripIngestion,
    timings: dict[str, Any] | None = None,
) -> list[PipelineSensorWindow]:
    parts_start = time.perf_counter()
    parts = list(
        ingestion.parts.filter(
            kind=PartKind.SENSOR_WINDOWS,
            received_at__isnull=False,
        ).order_by("sequence")
    )
    _add_elapsed_ms(timings, "raw_parts_query_ms", parts_start)
    if timings is not None:
        timings["raw_parts"] = len(parts)

    windows: list[PipelineSensorWindow] = []
    for part in parts:
        windows.extend(
            _load_raw_sensor_part_windows(part.object_key, timings=timings)
        )

    sort_start = time.perf_counter()
    sorted_windows = sorted(windows, key=lambda window: window.start_timestamp)
    _add_elapsed_ms(timings, "raw_sort_ms", sort_start)
    if timings is not None:
        timings["raw_windows"] = len(sorted_windows)
    return sorted_windows


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


def _distance_meters_from_postgis(trip: Trip) -> float:
    row = (
        Trip.objects.filter(pk=trip.pk)
        .annotate(path_length=Length("path"))
        .values("path_length")
        .get()
    )
    distance = row["path_length"]
    if distance is None:
        return 0
    return float(distance.m if hasattr(distance, "m") else distance)


def _build_trip_path(trip: Trip) -> int:
    """Deriva la LineString del viaggio dai GPS ordinati nel DB."""
    coords = [
        (point.x, point.y)
        for point in GpsPoint.objects.filter(trip=trip)
        .order_by("timestamp", "id")
        .values_list("point", flat=True)
    ]
    if len(set(coords)) < 2:
        trip.path = None
        trip.distance_meters = 0
        trip.save(update_fields=["path", "distance_meters", "updated_at"])
        return len(coords)

    trip.path = LineString(coords, srid=4326)
    trip.distance_meters = None
    trip.save(update_fields=["path", "distance_meters", "updated_at"])

    trip.distance_meters = _distance_meters_from_postgis(trip)
    trip.save(update_fields=["distance_meters", "updated_at"])
    return len(coords)


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
    with transaction.atomic():
        ingestion = (
            TripIngestion.objects.select_for_update()
            .select_related("user")
            .get(id=ingestion_id)
        )
        if ingestion.core_status == TripIngestion.PhaseStatus.COMPLETED:
            return {"skipped": "core ingestion already completed"}
        if ingestion.core_status not in CORE_CLAIMABLE_STATUSES:
            return _skip_result("core", ingestion.core_status)

        ingestion.core_status = TripIngestion.PhaseStatus.PROCESSING
        ingestion.started_processing_at = timezone.now()
        ingestion.save(
            update_fields=["core_status", "started_processing_at", "updated_at"]
        )

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
            path_point_count = _build_trip_path(trip)

            ingestion.trip = trip
            ingestion.core_status = TripIngestion.PhaseStatus.COMPLETED
            ingestion.error_message = ""
            ingestion.completed_at = timezone.now()
            ingestion.save(
                update_fields=[
                    "trip",
                    "core_status",
                    "error_message",
                    "completed_at",
                    "updated_at",
                ]
            )
    except Exception as exc:  # noqa: BLE001
        will_retry = self.request.retries < self.max_retries
        failed_at = timezone.now()
        ingestion.core_status = (
            TripIngestion.PhaseStatus.FAILED_RETRYABLE
            if will_retry
            else TripIngestion.PhaseStatus.FAILED_FINAL
        )
        ingestion.error_message = str(exc)
        ingestion.failed_at = failed_at
        update_fields = ["core_status", "error_message", "failed_at", "updated_at"]
        if (
            not will_retry
            and ingestion.recording_started_at is not None
            and ingestion.recording_closed_at is None
            and ingestion.recording_abandoned_at is None
        ):
            ingestion.recording_closed_at = failed_at
            update_fields.append("recording_closed_at")
        ingestion.save(update_fields=update_fields)
        if will_retry:
            raise self.retry(exc=exc)
        raise

    return {
        "trip_id": trip.id,
        "gps_points": gps_count,
        "path_points": path_point_count,
        "state_transitions": transition_count,
    }


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
        sensor_windows = _load_raw_sensor_windows(ingestion, timings=timings)
        _add_elapsed_ms(timings, "raw_load_total_ms", raw_load_start)
        with transaction.atomic():
            result = _run_pipeline_with_timings(
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
