from django.contrib import admin

from .models import GpsPoint, HarJob, SensorWindow, Trip


@admin.register(Trip)
class TripAdmin(admin.ModelAdmin):
    list_display = ("id", "device_id", "status", "started_at", "ended_at", "created_at")
    list_filter = ("status", "created_at")
    search_fields = ("id", "device_id")


@admin.register(GpsPoint)
class GpsPointAdmin(admin.ModelAdmin):
    list_display = ("id", "trip", "timestamp", "latitude", "longitude", "speed_mps")
    list_filter = ("timestamp",)


@admin.register(SensorWindow)
class SensorWindowAdmin(admin.ModelAdmin):
    list_display = ("id", "trip", "start_timestamp", "end_timestamp", "sample_count", "frequency_hz")
    list_filter = ("start_timestamp", "frequency_hz")


@admin.register(HarJob)
class HarJobAdmin(admin.ModelAdmin):
    list_display = ("id", "trip", "kind", "status", "created_at", "updated_at")
    list_filter = ("kind", "status", "created_at")

