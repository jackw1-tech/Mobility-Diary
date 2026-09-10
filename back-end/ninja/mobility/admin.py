from django.contrib import admin
from django.db import connection
from django.utils.html import format_html, format_html_join

from .models import (
    CandidateVisit,
    GpsPoint,
    HabitualPlace,
    HarJob,
    MobilitySegment,
    RawSensorReading,
    StateTransition,
    Trip,
    TripUpload,
    TripUploadPart,
    VirtualStopInterval,
    PlaceMiningStatus,
)


_SENSOR_GAP_THRESHOLD_MS = 10

_SENSOR_GAP_QUERY = """
    WITH ordered AS (
        SELECT
            timestamp,
            LAG(timestamp) OVER (ORDER BY timestamp) AS prev_timestamp
        FROM {table}
        WHERE trip_id = %s
    )
    SELECT prev_timestamp, timestamp, timestamp - prev_timestamp AS gap
    FROM ordered
    WHERE timestamp - prev_timestamp > (%s * INTERVAL '1 millisecond')
    ORDER BY prev_timestamp
"""


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
    readonly_fields = ("sensor_gaps",)

    @admin.display(
        description=f"Buchi registrazione sensori (>{_SENSOR_GAP_THRESHOLD_MS}ms)"
    )
    def sensor_gaps(self, obj):
        if obj.pk is None:
            return "-"
        table = connection.ops.quote_name(RawSensorReading._meta.db_table)
        with connection.cursor() as cursor:
            cursor.execute(
                _SENSOR_GAP_QUERY.format(table=table),
                [obj.pk, _SENSOR_GAP_THRESHOLD_MS],
            )
            rows = cursor.fetchall()
        if not rows:
            return "Nessun buco rilevato"
        return format_html(
            "<ul>{}</ul>",
            format_html_join(
                "",
                "<li>{} → {} (buco di {})</li>",
                rows,
            ),
        )


@admin.register(GpsPoint)
class GpsPointAdmin(admin.ModelAdmin):
    list_display = ("id", "trip", "timestamp", "latitude", "longitude", "speed_mps")
    list_filter = ("timestamp",)


@admin.register(StateTransition)
class StateTransitionAdmin(admin.ModelAdmin):
    list_display = ("id", "trip", "from_state", "to_state", "timestamp")
    list_filter = ("to_state", "timestamp")


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
    list_display = ("id", "trip", "status", "created_at", "updated_at")
    list_filter = ("status", "created_at")
    raw_id_fields = ("trip",)


class TripUploadPartInline(admin.TabularInline):
    model = TripUploadPart
    extra = 0
    fields = ("sequence", "object_key", "received_at", "created_at")
    readonly_fields = ("created_at",)


@admin.register(TripUpload)
class TripUploadAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "user",
        "client_session_id",
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
        "created_at",
    )
    search_fields = (
        "id",
        "user__email",
        "client_session_id",
        "device_id",
        "raw_base_path",
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
    inlines = (TripUploadPartInline,)
    ordering = ("-created_at",)


@admin.register(TripUploadPart)
class TripUploadPartAdmin(admin.ModelAdmin):
    list_display = (
        "id",
        "upload",
        "sequence",
        "received_at",
        "created_at",
    )
    list_filter = ("received_at", "created_at")
    search_fields = ("id", "upload__client_session_id", "object_key", "sha256")
    readonly_fields = ("created_at",)
    raw_id_fields = ("upload",)
    ordering = ("-created_at",)

@admin.register(PlaceMiningStatus)
class PlaceMiningStatusAdmin(admin.ModelAdmin):
    list_display = ("id", "user", "status", "updated_at")
    list_filter = ("status", "updated_at")
    search_fields = ("id", "user__email")
    raw_id_fields = ("user",)

