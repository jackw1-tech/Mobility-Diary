from django.contrib import admin
from django.urls import path
from ninja import NinjaAPI
from ninja.openapi.docs import Swagger

from accounts.auth_mobile.api import router as auth_router
from accounts.privacy.api import router as privacy_router
from accounts.auth_web.api import router as web_auth_router
from accounts.auth_web.users_api import router as web_users_router
from mobility.api import router as mobility_router
from mobility.upload.api import router as upload_router

OPENAPI_TAGS = [
    {
        "name": "auth",
        "description": "Registrazione, login e sessione dell'app mobile.",
    },
    {
        "name": "privacy",
        "description": "Lettura e aggiornamento delle preferenze privacy personali.",
    },
    {
        "name": "web-auth",
        "description": "Autenticazione e rinnovo della sessione della piattaforma web.",
    },
    {
        "name": "web-users",
        "description": "Consultazione staff degli utenti e dei relativi viaggi.",
    },
    {
        "name": "mobility",
        "description": "Diario, viaggi, luoghi significativi e analitiche personali.",
    },
    {
        "name": "upload",
        "description": "Avvio, caricamento e completamento dell'upload dei viaggi.",
    },
]

api = NinjaAPI(
    title="Mobility Diary API",
    version="1.0.0",
    description=(
        "API del Diario della Mobilità per l'app mobile e la piattaforma web. "
        "Gli endpoint protetti supportano l'autenticazione Bearer tramite il "
        "pulsante **Authorize** di Swagger UI."
    ),
    docs=Swagger(
        settings={
            "displayRequestDuration": True,
            "persistAuthorization": True,
        }
    ),
    docs_url="/docs",
    openapi_url="/openapi.json",
    openapi_extra={"tags": OPENAPI_TAGS},
)
api.add_router("/auth/", auth_router)
api.add_router("/privacy/", privacy_router)
api.add_router("/web/auth/", web_auth_router)
api.add_router("/web/", web_users_router)
api.add_router("/mobility/", mobility_router)
api.add_router("/upload/", upload_router)

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/", api.urls),
]
