from django.contrib import admin
from django.urls import path
from ninja import NinjaAPI

from mobility.api import router as mobility_router

api = NinjaAPI(title="Mobility Diary API", version="0.1.0")
api.add_router("/mobility/", mobility_router)

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/", api.urls),
]

