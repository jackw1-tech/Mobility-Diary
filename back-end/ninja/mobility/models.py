from django.conf import settings
from django.db import models


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
    device_id = models.CharField(max_length=128)
    status = models.CharField(max_length=32, choices=Status.choices, default=Status.OPEN)
    started_at = models.DateTimeField(auto_now_add=True)
    ended_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self) -> str:
        return f"Trip {self.id} ({self.status})"


class GpsPoint(models.Model):
    trip = models.ForeignKey(Trip, related_name="gps_points", on_delete=models.CASCADE)
    timestamp = models.DateTimeField()
    latitude = models.DecimalField(max_digits=9, decimal_places=6)
    longitude = models.DecimalField(max_digits=9, decimal_places=6)
    speed_mps = models.FloatField(default=0)
    accuracy_meters = models.FloatField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [
            models.Index(fields=["trip", "timestamp"]),
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
