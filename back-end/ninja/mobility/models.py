from django.conf import settings
from django.contrib.gis.db import models
from django.contrib.postgres.indexes import GistIndex


class ActivityLabel(models.TextChoices):
    IDLE = "IDLE", "Idle"
    WALKING = "WALKING", "Walking"
    RUNNING = "RUNNING", "Running"
    BIKING = "BIKING", "Biking"
    MOVING_VEHICLE = "MOVING_VEHICLE", "Moving vehicle"


class Trip(models.Model):
    class Status(models.TextChoices):
        OPEN = "OPEN", "Open"
        CLOSED = "CLOSED", "Closed"
        PROCESSED = "PROCESSED", "Processed"

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name="trips",
        on_delete=models.CASCADE,
        null=True,
        blank=True,
    )
    # UUID della sessione FSM locale, usato come chiave di idempotenza per il sync.
    client_session_id = models.CharField(
        max_length=64, null=True, blank=True, unique=True
    )
    device_id = models.CharField(max_length=128)
    status = models.CharField(max_length=32, choices=Status.choices, default=Status.OPEN)
    path = models.LineStringField(
        geography=True,
        srid=4326,
        null=True,
        blank=True,
        spatial_index=False,
    )
    distance_meters = models.FloatField(null=True, blank=True)
    started_at = models.DateTimeField(auto_now_add=True)
    ended_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = [
            GistIndex(fields=["path"]),
        ]

    def __str__(self) -> str:
        return f"Trip {self.id} ({self.status})"


class GpsPoint(models.Model):
    trip = models.ForeignKey(Trip, related_name="gps_points", on_delete=models.CASCADE)
    timestamp = models.DateTimeField()
    point = models.PointField(geography=True)
    speed_mps = models.FloatField(default=0)
    accuracy_meters = models.FloatField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [
            models.Index(fields=["trip", "timestamp"]),
        ]
        constraints = [
            models.UniqueConstraint(
                fields=["trip", "timestamp"],
                name="unique_gps_point_per_trip_timestamp",
            )
        ]

    @property
    def latitude(self) -> float:
        return self.point.y

    @property
    def longitude(self) -> float:
        return self.point.x


class StateTransition(models.Model):
    trip = models.ForeignKey(
        Trip, related_name="state_transitions", on_delete=models.CASCADE
    )
    from_state = models.CharField(max_length=32)
    to_state = models.CharField(max_length=32)
    reason = models.CharField(max_length=128, blank=True)
    timestamp = models.DateTimeField()
    sigma = models.FloatField(null=True, blank=True)
    speed_mps = models.FloatField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [
            models.Index(fields=["trip", "timestamp"], name="mobility_st_trip_id_idx"),
        ]
        constraints = [
            models.UniqueConstraint(
                fields=["trip", "timestamp", "to_state"],
                name="unique_state_transition_per_trip_time",
            )
        ]


class SensorWindow(models.Model):
    trip = models.ForeignKey(Trip, related_name="sensor_windows", on_delete=models.CASCADE)
    start_timestamp = models.DateTimeField()
    end_timestamp = models.DateTimeField()
    sample_count = models.PositiveIntegerField()
    frequency_hz = models.PositiveIntegerField()
    matrix = models.JSONField(null=True, blank=True)
    object_key = models.CharField(max_length=512, blank=True)
    is_synced = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [
            models.Index(fields=["trip", "start_timestamp"]),
        ]
        constraints = [
            models.UniqueConstraint(
                fields=["trip", "start_timestamp", "end_timestamp"],
                name="unique_sensor_window_per_trip_time_range",
            )
        ]


class SignificantPlace(models.Model):
    trip = models.ForeignKey(
        Trip, related_name="significant_places", on_delete=models.CASCADE
    )
    center = models.PointField(geography=True)
    radius_meters = models.FloatField(default=0)
    dwell_seconds = models.PositiveIntegerField(default=0)
    label = models.CharField(max_length=128, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    @property
    def latitude(self) -> float:
        return self.center.y

    @property
    def longitude(self) -> float:
        return self.center.x


class MobilitySegment(models.Model):
    """Una riga del diario: una sosta (STOP) o uno spostamento (MOVE)."""

    class Kind(models.TextChoices):
        STOP = "STOP", "Stop"
        MOVE = "MOVE", "Move"

    trip = models.ForeignKey(Trip, related_name="segments", on_delete=models.CASCADE)
    kind = models.CharField(max_length=8, choices=Kind.choices)
    start_timestamp = models.DateTimeField()
    end_timestamp = models.DateTimeField()
    activity_label = models.CharField(
        max_length=32, choices=ActivityLabel.choices, default=ActivityLabel.IDLE
    )
    place = models.ForeignKey(
        SignificantPlace,
        related_name="segments",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
    )
    distance_meters = models.FloatField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["start_timestamp"]
        indexes = [
            models.Index(fields=["trip", "start_timestamp"], name="mobility_seg_trip_id_idx"),
        ]


class HarJob(models.Model):
    class Kind(models.TextChoices):
        LIVE_BATCH = "LIVE_BATCH", "Live batch"
        FINAL_TRIP = "FINAL_TRIP", "Final trip"

    class Status(models.TextChoices):
        PENDING = "PENDING", "Pending"
        STARTED = "STARTED", "Started"
        SUCCESS = "SUCCESS", "Success"
        FAILURE = "FAILURE", "Failure"

    trip = models.ForeignKey(Trip, related_name="har_jobs", on_delete=models.CASCADE)
    kind = models.CharField(max_length=32, choices=Kind.choices)
    status = models.CharField(max_length=32, choices=Status.choices, default=Status.PENDING)
    result = models.JSONField(null=True, blank=True)
    error = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)


class PartKind(models.TextChoices):
    GPS_POINTS = "gps_points", "GPS points"
    STATE_TRANSITIONS = "state_transitions", "State transitions"
    SENSOR_WINDOWS = "sensor_windows", "Sensor windows"


class TripIngestion(models.Model):
    """Aggregato di upload, separato dal Trip di dominio.

    L'upload sporco (parti parziali, retry, fallimenti) vive qui; il Trip lo
    materializza Celery solo a processing riuscito, cosi' la tabella Trip
    contiene solo viaggi puliti (REPORT_STRATEGIA_INGESTION_ASINCRONA.md D6).
    """

    class PhaseStatus(models.TextChoices):
        PENDING = "PENDING", "Pending"
        RECEIVING = "RECEIVING", "Receiving"
        RECEIVED = "RECEIVED", "Received"
        QUEUED = "QUEUED", "Queued"
        PROCESSING = "PROCESSING", "Processing"
        COMPLETED = "COMPLETED", "Completed"
        FAILED_RETRYABLE = "FAILED_RETRYABLE", "Failed (retryable)"
        FAILED_FINAL = "FAILED_FINAL", "Failed (final)"

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        related_name="trip_ingestions",
        on_delete=models.CASCADE,
    )
    # Chiave di idempotenza dell'upload: stessa sessione mobile -> stessa ingestion.
    client_session_id = models.CharField(max_length=64)
    device_id = models.CharField(max_length=128, blank=True)
    schema_version = models.PositiveIntegerField(default=1)
    core_status = models.CharField(
        max_length=32,
        choices=PhaseStatus.choices,
        default=PhaseStatus.PENDING,
    )
    raw_status = models.CharField(
        max_length=32,
        choices=PhaseStatus.choices,
        default=PhaseStatus.PENDING,
    )
    # {"gps_points": 1, "state_transitions": 1}
    expected_core_parts = models.JSONField(default=dict)
    # {"sensor_windows": 6}
    expected_raw_parts = models.JSONField(default=dict)
    # Prefisso degli oggetti raw nello storage, es. "ingestions/<id>/".
    raw_base_path = models.CharField(max_length=512, blank=True)
    manifest_sha256 = models.CharField(max_length=64, blank=True)
    total_size_bytes = models.BigIntegerField(default=0)

    # Metadati del viaggio, dichiarati dal client.
    started_at = models.DateTimeField(null=True, blank=True)
    ended_at = models.DateTimeField(null=True, blank=True)
    timezone = models.CharField(max_length=64, blank=True)
    app_version = models.CharField(max_length=32, blank=True)
    device_platform = models.CharField(max_length=32, blank=True)

    # Trip materializzato da Celery (null finche' non processato).
    trip = models.ForeignKey(
        Trip,
        related_name="ingestions",
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
    )

    error_message = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    queued_at = models.DateTimeField(null=True, blank=True)
    started_processing_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    failed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [
            models.Index(fields=["user", "core_status"]),
            models.Index(fields=["user", "raw_status"]),
        ]
        constraints = [
            models.UniqueConstraint(
                fields=["user", "client_session_id"],
                name="unique_ingestion_per_user_session",
            )
        ]

    def __str__(self) -> str:
        return (
            f"TripIngestion {self.id} "
            f"(core={self.core_status}, raw={self.raw_status})"
        )


class TripIngestionPart(models.Model):
    ingestion = models.ForeignKey(
        TripIngestion, related_name="parts", on_delete=models.CASCADE
    )
    kind = models.CharField(max_length=32, choices=PartKind.choices)
    sequence = models.PositiveIntegerField()
    sha256 = models.CharField(max_length=64)
    size_bytes = models.BigIntegerField(default=0)
    object_key = models.CharField(max_length=512)
    # Valorizzato in 'confirm', quando il blob risulta presente sullo storage.
    received_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["ingestion", "kind", "sequence"],
                name="unique_part_per_ingestion_kind_sequence",
            )
        ]

    def __str__(self) -> str:
        return f"{self.kind}#{self.sequence} of ingestion {self.ingestion_id}"
