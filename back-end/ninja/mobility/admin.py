from django.contrib import admin

from .models import (
    GpsPoint,
    HarJob,
    MobilitySegment,
    SensorWindow,
    SignificantPlace,
    StateTransition,
    Trip,
)


@admin.register(Trip)
class TripAdmin(admin.ModelAdmin):
    list_display = ("id", "device_id", "client_session_id", "status", "started_at", "ended_at")
    list_filter = ("status", "created_at")
    search_fields = ("id", "device_id", "client_session_id")


@admin.register(GpsPoint)
class GpsPointAdmin(admin.ModelAdmin):
    list_display = ("id", "trip", "timestamp", "latitude", "longitude", "speed_mps")
    list_filter = ("timestamp",)


@admin.register(StateTransition)
class StateTransitionAdmin(admin.ModelAdmin):
    list_display = ("id", "trip", "from_state", "to_state", "timestamp")
    list_filter = ("to_state", "timestamp")


@admin.register(SensorWindow)
class SensorWindowAdmin(admin.ModelAdmin):
    list_display = ("id", "trip", "start_timestamp", "end_timestamp", "sample_count", "frequency_hz", "is_synced")
    list_filter = ("start_timestamp", "frequency_hz", "is_synced")


@admin.register(SignificantPlace)
class SignificantPlaceAdmin(admin.ModelAdmin):
    list_display = ("id", "trip", "latitude", "longitude", "radius_meters", "dwell_seconds", "label")


@admin.register(MobilitySegment)
class MobilitySegmentAdmin(admin.ModelAdmin):
    list_display = ("id", "trip", "kind", "activity_label", "start_timestamp", "end_timestamp", "distance_meters")
    list_filter = ("kind", "activity_label")


@admin.register(HarJob)
class HarJobAdmin(admin.ModelAdmin):
    list_display = ("id", "trip", "kind", "status", "created_at", "updated_at")
    list_filter = ("kind", "status", "created_at")
