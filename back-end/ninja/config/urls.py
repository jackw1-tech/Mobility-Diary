from django.contrib import admin
from django.urls import path
from ninja import NinjaAPI

from accounts.api import router as auth_router
from accounts.privacy_api import router as privacy_router
from accounts.web_api import router as web_auth_router
from accounts.web_users_api import router as web_users_router
from mobility.api import router as mobility_router
from mobility.ingestion.api import router as ingestion_router

api = NinjaAPI(title="Mobility Diary API", version="0.1.0")
api.add_router("/auth/", auth_router)
api.add_router("/privacy/", privacy_router)
api.add_router("/web/auth/", web_auth_router)
api.add_router("/web/", web_users_router)
api.add_router("/mobility/", mobility_router)
api.add_router("/ingestion/", ingestion_router)

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/", api.urls),
]
