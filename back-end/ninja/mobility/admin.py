from django.contrib import admin

from .models import (
    CandidateVisit,
    GpsPoint,
    HabitualPlace,
    HarJob,
    MobilitySegment,
    SensorWindow,
    StateTransition,
    Trip,
    TripIngestion,
    TripIngestionPart,
    VirtualStopInterval,
    PlaceMiningStatus,
)


@admin.register(Trip)
class TripAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "device_id",
        "client_session_id",
        "status",
        "is_reloadable",
        "note",
        "started_at",
        "ended_at",
    )
    list_filter = ("status", "is_reloadable", "created_at")
    search_fields = ("id", "device_id", "client_session_id", "note")


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


@admin.register(HabitualPlace)
class HabitualPlaceAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "user",
        "state",
        "category",
        "custom_name",
        "latitude",
        "longitude",
        "visit_count",
        "distinct_days",
    )
    list_filter = ("state", "category")
    search_fields = ("id", "user__email", "custom_name")

    @admin.display(description="Lat")
    def latitude(self, obj):
        return obj.center.y

    @admin.display(description="Lon")
    def longitude(self, obj):
        return obj.center.x


@admin.register(CandidateVisit)
class CandidateVisitAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "user",
        "place",
        "latitude",
        "longitude",
        "started_at",
        "ended_at",
        "point_count",
    )
    list_filter = ("started_at", "ended_at")
    search_fields = ("id", "user__email", "place__custom_name")
    raw_id_fields = ("user", "place")

    @admin.display(description="Lat")
    def latitude(self, obj):
        return obj.center.y

    @admin.display(description="Lon")
    def longitude(self, obj):
        return obj.center.x


@admin.register(MobilitySegment)
class MobilitySegmentAdmin(admin.ModelAdmin):
    list_display = ("id", "trip", "kind", "activity_label", "start_timestamp", "end_timestamp", "distance_meters")
    list_filter = ("kind", "activity_label")
    raw_id_fields = ("trip",)


@admin.register(VirtualStopInterval)
class VirtualStopIntervalAdmin(admin.ModelAdmin):
    list_display = ("id", "trip", "start_timestamp", "end_timestamp", "created_at")
    list_filter = ("start_timestamp", "end_timestamp", "created_at")
    search_fields = ("id", "trip__client_session_id", "trip__user__email")
    raw_id_fields = ("trip",)


@admin.register(HarJob)
class HarJobAdmin(admin.ModelAdmin):
    list_display = ("id", "trip", "kind", "status", "created_at", "updated_at")
    list_filter = ("kind", "status", "created_at")
    raw_id_fields = ("trip",)


class TripIngestionPartInline(admin.TabularInline):
    model = TripIngestionPart
    extra = 0
    fields = ("kind", "sequence", "size_bytes", "object_key", "received_at", "created_at")
    readonly_fields = ("created_at",)


@admin.register(TripIngestion)
class TripIngestionAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "user",
        "client_session_id",
        "core_ingestion_mode",
        "core_status",
        "raw_status",
        "trip",
        "device_id",
        "created_at",
        "updated_at",
    )
    list_filter = (
        "core_status",
        "raw_status",
        "core_ingestion_mode",
        "schema_version",
        "device_platform",
        "created_at",
    )
    search_fields = (
        "id",
        "user__email",
        "client_session_id",
        "device_id",
        "raw_base_path",
        "manifest_sha256",
        "core_payload_sha256",
        "error_message",
    )
    readonly_fields = (
        "created_at",
        "updated_at",
        "queued_at",
        "started_processing_at",
        "completed_at",
        "failed_at",
    )
    raw_id_fields = ("user", "trip")
    inlines = (TripIngestionPartInline,)
    ordering = ("-created_at",)


@admin.register(TripIngestionPart)
class TripIngestionPartAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "ingestion",
        "kind",
        "sequence",
        "size_bytes",
        "received_at",
        "created_at",
    )
    list_filter = ("kind", "received_at", "created_at")
    search_fields = ("id", "ingestion__client_session_id", "object_key", "sha256")
    readonly_fields = ("created_at",)
    raw_id_fields = ("ingestion",)
    ordering = ("-created_at",)

@admin.register(PlaceMiningStatus)
class PlaceMiningStatusAdmin(admin.ModelAdmin):
    list_display = ("id", "user", "status", "updated_at")
    list_filter = ("status", "updated_at")
    search_fields = ("id", "user__email")
    raw_id_fields = ("user",)
