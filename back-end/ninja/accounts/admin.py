from django.contrib import admin

from .models import AccessToken


@admin.register(AccessToken)
class AccessTokenAdmin(admin.ModelAdmin):
    list_display = (
        "user",
        "device_name",
        "created_at",
        "expires_at",
        "last_used_at",
        "revoked_at",
    )
    list_filter = ("revoked_at",)
    search_fields = ("user__email", "device_name", "user_agent")
    readonly_fields = ("token_hash", "created_at", "last_used_at")
    raw_id_fields = ("user",)
    ordering = ("-created_at",)
