from datetime import timedelta

from celery import shared_task
from celery.signals import worker_process_init
from django.db import transaction
from django.utils import timezone

from .upload import selectors as upload_repository
from .upload.raw_sensor_loader import load_raw_sensor_windows
from .models import (
    HarJob,
    PlaceMiningStatus,
    Trip,
    TripUpload,
)
from .ml.har_adapter import warm_har_model
from .ml.pipeline import run_pipeline
from .selectors import har_jobs as har_jobs_repository
from .selectors import place_mining_status as place_mining_status_repository
from .selectors.sensor_readings import (
    replace_raw_sensor_readings,
    replace_raw_sensor_readings_from_source,
)
from .significant_places import mine_user_significant_places

"""
Chiamata da reload / caricamnto diretto
Aggiorna i campi di TripUpload per indiciare che sta cominciando il caricamento della parte raw del viaggio ricaricato
"""
@shared_task(bind=True, max_retries=3, retry_backoff=True, default_retry_delay=30)
def prepare_reloaded_trip_raw(
    self,
    upload_id: int,
    source_trip_id: int,
    shift_microseconds: int,
) -> dict:
    try:
        with transaction.atomic():
            upload = upload_repository.locked_trip_upload_by_id(upload_id)
            # protezione per non farlo avvenire due volte
            if upload.raw_status in {
                TripUpload.PhaseStatus.QUEUED,
                TripUpload.PhaseStatus.PROCESSING,
                TripUpload.PhaseStatus.COMPLETED,
            }:
                return {
                    "upload_id": upload.id,
                    "raw_status": upload.raw_status,
                    "already_prepared": True,
                }

            source = Trip.objects.get(id=source_trip_id)
            if upload.trip_id is None or upload.source_trip_id != source.id:
                raise ValueError("reload raw incoerente con il viaggio sorgente")

            upload.raw_status = TripUpload.PhaseStatus.RECEIVING
            upload.started_processing_at = timezone.now()
            upload.error_message = ""
            upload.save(
                update_fields=[
                    "raw_status",
                    "started_processing_at",
                    "error_message",
                    "updated_at",
                ]
            )

            from .replay_raw import regenerate_raw_and_queue_har

            regenerate_raw_and_queue_har(
                upload,
                source,
                shift=timedelta(microseconds=shift_microseconds),
                now=upload.ended_at or timezone.now(),
            )

        return {
            "upload_id": upload.id,
            "raw_status": upload.raw_status,
            "already_prepared": False,
        }
    except Exception as exc:
        will_retry = self.request.retries < self.max_retries
        with transaction.atomic():
            upload = upload_repository.locked_trip_upload_by_id(upload_id)
            upload.raw_status = (
                TripUpload.PhaseStatus.FAILED_RETRYABLE
                if will_retry
                else TripUpload.PhaseStatus.FAILED_FINAL
            )
            upload.error_message = str(exc)
            upload.failed_at = timezone.now()
            upload.save(
                update_fields=[
                    "raw_status",
                    "error_message",
                    "failed_at",
                    "updated_at",
                ]
            )
        if will_retry:
            raise self.retry(exc=exc)
        raise


_PLACE_MINING_PENDING_FIELDS = [
    "status",
    "requested_at",
    "started_at",
    "finished_at",
    "error_message",
    "rerun_requested",
]


@worker_process_init.connect #eseguita ogni volta che nasce un processo worker
def warm_har_model_on_worker_start(**_kwargs) -> None:
    warm_har_model()

# Ottieni il lock sul place mining status di quell'utente
def _place_mining_status_for_update(user_id: int) -> PlaceMiningStatus:
    return place_mining_status_repository.locked_status_for_user(
        user_id,
        default_status=PlaceMiningStatus.Status.IDLE,
        requested_at=timezone.now(),
    )

# Imposta il place mining status a pending
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

# Controlla che per quell'utente non c'è già stato un altro viaggio ravvicinato che ha richiesto il mining, se si, imposto rerun_requested a true in questo modo quando 
# l'altro finirà, rischedulerà lui un altro task uguale
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

#Aggiorna lo status del place mining in running e controlla se non ne è già in corso uno
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

"""Controllo se nel mentre che questa esecuzione del mining è arrivata un altra richiesta"""
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


#Task asincrono per l'analisi dei luoghi significativi
@shared_task(bind=True, max_retries=3, retry_backoff=True)
def mine_significant_places(self, user_id: int) -> dict:
    if not _begin_place_mining_run(user_id):
        return {"skipped": "place mining not pending"}
    result = mine_user_significant_places(user_id)
    if _finish_place_mining_run(
        user_id,
        status_value=PlaceMiningStatus.Status.SUCCEEDED,
    ):
        _schedule_place_mining(user_id) ## Se qualcun'altro nel mentre ha impostato rerun_requested = true, rischedula un altro task
    return result

#Metti in coda il task di mining dei punti gps
def _schedule_place_mining(user_id: int) -> None:
    transaction.on_commit(lambda: mine_significant_places.delay(user_id))

#Wrapper della funzione che aggiorna Har Job
def _merge_har_job_result(job_id: int, updates: dict) -> dict:
    return har_jobs_repository.merge_har_job_result(job_id, updates)


"Inserimento Batch dei dati raw"
@shared_task(bind=True, max_retries=3, retry_backoff=True, default_retry_delay=30)
def persist_trip_raw_sensor_readings(
    self,
    job_id: int,
    upload_id: int,
    raw_clone_shift_microseconds: int | None = None,
) -> dict:
    trip_id = None
    try:
        upload = upload_repository.trip_upload_with_trip(upload_id)
        job = har_jobs_repository.har_job_for_raw_persistence(job_id)
        trip = upload.trip or job.trip
        if trip is None:
            raise ValueError("trip non disponibile per la persistenza raw sensor")
        trip_id = trip.id

        cloned = _clone_derived_raw_sensor_readings(
            trip,
            raw_clone_shift_microseconds,
        )
        if cloned is not None:
            _merge_har_job_result(
                job_id,
                {
                    "raw_readings_persisted": cloned,
                    "raw_readings_persistence_status": "COMPLETED",
                    "raw_readings_persistence_mode": "cloned_from_source",
                },
            )
            return {
                "trip_id": trip_id,
                "raw_readings_persisted": cloned,
                "raw_readings_persistence_status": "COMPLETED",
            }

        #Voglio inserire dati har di un viaggio che non è un clone -> funzione veloce grazie alla cache
        sensor_windows = load_raw_sensor_windows(upload)

        persisted_readings = replace_raw_sensor_readings(trip, sensor_windows)

        _merge_har_job_result(
            job_id,
            {
                "raw_readings_persisted": persisted_readings,
                "raw_readings_persistence_status": "COMPLETED",
            },
        )
        return {
            "trip_id": trip_id,
            "raw_readings_persisted": persisted_readings,
            "raw_readings_persistence_status": "COMPLETED",
        }
    except Exception as exc:
        will_retry = self.request.retries < self.max_retries
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

"""Funzione principale di analisi dei dati raw"""
@shared_task(bind=True, max_retries=3, default_retry_delay=30)
def process_trip_har_final(
    self,
    job_id: int,
    upload_id: int,
    raw_clone_shift_microseconds: int | None = None,
) -> dict:
#Sezione di preparazione (cambio di stato d TripUpload e HarJob)
    with transaction.atomic():
        upload = upload_repository.locked_trip_upload_by_id(upload_id)
        job = har_jobs_repository.locked_har_job_for_processing(job_id)
        trip = upload.trip or job.trip

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

# Sezione centrale, scarico tutti i dati dall'objet e interrogo l AI
    try:
        sensor_windows = load_raw_sensor_windows(upload)

        with transaction.atomic():
            result = run_pipeline(
                trip,
                sensor_windows=sensor_windows,
            )
            result["raw_readings_persisted"] = None
            result["raw_readings_persistence_status"] = "QUEUED"

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
            job.save(update_fields=["status", "result", "error", "updated_at"]) #Per il front end l'intero processo finisce qui

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
        if will_retry:
            raise self.retry(exc=exc)
        raise

    # Mette in coda il task di inserimento batch
    try:
        persist_trip_raw_sensor_readings.delay(
            job_id, upload_id, raw_clone_shift_microseconds
        )
    except Exception as exc:
        _merge_har_job_result(
            job_id,
            {
                "raw_readings_persisted": 0,
                "raw_readings_persistence_status": "FAILED",
                "raw_readings_persistence_error": str(exc),
            },
        )

    # Mette in coda il task di mining dei punti gps
    if _request_place_mining(trip.user_id):
        _schedule_place_mining(trip.user_id)

    return result


# Decide se i dati raw possono essere clonati da un altro trip (caso replay) e prova a farlo
def _clone_derived_raw_sensor_readings(
    trip: Trip,
    shift_microseconds: int | None,
) -> int | None:
    if shift_microseconds is None or trip.reloaded_from_trip_id is None:
        return None
    source = Trip.objects.filter(id=trip.reloaded_from_trip_id).first()
    if source is None:
        return None

    cloned = replace_raw_sensor_readings_from_source(
        trip,
        source,
        shift=timedelta(microseconds=shift_microseconds),
    )
    if cloned:
        return cloned
    return None
