from django.contrib import admin

from .models import AccessToken, UserPrivacySettings


@admin.register(AccessToken)
class AccessTokenAdmin(admin.ModelAdmin):
    list_display = (
        "user",
        "created_at",
        "expires_at",
        "revoked_at",
    )
    list_filter = ("revoked_at",)
    search_fields = ("user__email",)
    readonly_fields = ("token_hash", "created_at")
    raw_id_fields = ("user",)
    ordering = ("-created_at",)


@admin.register(UserPrivacySettings)
class UserPrivacySettingsAdmin(admin.ModelAdmin):
    list_display = ("user", "level", "updated_at")
    list_filter = ("level",)
    search_fields = ("user__email",)
    raw_id_fields = ("user",)
    readonly_fields = ("created_at", "updated_at")
