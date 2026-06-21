import os
from pathlib import Path

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
ENV_FILE = os.getenv("DJANGO_ENV_FILE")
if ENV_FILE:
    load_dotenv(BASE_DIR / ENV_FILE)
else:
    load_dotenv(BASE_DIR / ".env.local")


def env_bool(name: str, default: bool = False) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.lower() in {"1", "true", "yes", "on"}


def env_list(name: str, default: str = "") -> list[str]:
    raw_value = os.getenv(name, default)
    return [item.strip() for item in raw_value.split(",") if item.strip()]


def unique(values: list[str]) -> list[str]:
    seen = set()
    result = []
    for value in values:
        if value not in seen:
            seen.add(value)
            result.append(value)
    return result


def normalize_host(host: str) -> str:
    return host.removeprefix("https://").removeprefix("http://").split("/")[0]


def normalize_csrf_origin(origin: str) -> str:
    if origin.startswith(("http://", "https://")):
        return origin.rstrip("/")
    return f"https://{origin.rstrip('/')}"


RAILWAY_PUBLIC_DOMAIN = os.getenv("RAILWAY_PUBLIC_DOMAIN", "").strip()

SECRET_KEY = os.getenv("DJANGO_SECRET_KEY", "unsafe-dev-secret-key")
DEBUG = env_bool("DJANGO_DEBUG", True)
ALLOWED_HOSTS = unique(
    [
        normalize_host(host)
        for host in env_list("DJANGO_ALLOWED_HOSTS", "localhost,127.0.0.1")
        + ([RAILWAY_PUBLIC_DOMAIN] if RAILWAY_PUBLIC_DOMAIN else [])
    ]
)
CSRF_TRUSTED_ORIGINS = unique(
    [
        normalize_csrf_origin(origin)
        for origin in env_list("CSRF_TRUSTED_ORIGINS")
        + ([RAILWAY_PUBLIC_DOMAIN] if RAILWAY_PUBLIC_DOMAIN else [])
    ]
)

INSTALLED_APPS = [
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "django.contrib.gis",
    "accounts",
    "mobility",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.debug",
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

WSGI_APPLICATION = "config.wsgi.application"

DATABASES = {
    "default": {
        "ENGINE": "django.contrib.gis.db.backends.postgis",
        "NAME": os.getenv("POSTGRES_DB", os.getenv("PGDATABASE", "mobility")),
        "USER": os.getenv("POSTGRES_USER", os.getenv("PGUSER", "mobility")),
        "PASSWORD": os.getenv("POSTGRES_PASSWORD", os.getenv("PGPASSWORD", "mobility")),
        "HOST": os.getenv("POSTGRES_HOST", os.getenv("PGHOST", "localhost")),
        "PORT": os.getenv("POSTGRES_PORT", os.getenv("PGPORT", "5432")),
    }
}

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "it-it"
TIME_ZONE = "Europe/Rome"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
STORAGES = {
    "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {
        "BACKEND": "whitenoise.storage.CompressedManifestStaticFilesStorage",
    },
}

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
USE_X_FORWARDED_HOST = env_bool("USE_X_FORWARDED_HOST", bool(RAILWAY_PUBLIC_DOMAIN))

SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SAMESITE = "Lax"
SESSION_COOKIE_SECURE = env_bool("SESSION_COOKIE_SECURE", not DEBUG)
CSRF_COOKIE_HTTPONLY = False
CSRF_COOKIE_SAMESITE = "Lax"
CSRF_COOKIE_SECURE = env_bool("CSRF_COOKIE_SECURE", not DEBUG)
MOBILE_ACCESS_TOKEN_TTL_DAYS = int(os.getenv("MOBILE_ACCESS_TOKEN_TTL_DAYS", "30"))

REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6381/0")
CELERY_BROKER_URL = os.getenv("CELERY_BROKER_URL", REDIS_URL)
CELERY_RESULT_BACKEND = os.getenv("CELERY_RESULT_BACKEND", "redis://localhost:6381/1")
CELERY_TASK_TRACK_STARTED = True
CELERY_TASK_TIME_LIMIT = 30 * 60

# Object storage S3-compatibile per l'ingestione asincrona dei viaggi.
# MinIO in locale, Railway Buckets in deploy (vedi REPORT_STRATEGIA_INGESTION_ASINCRONA.md D7).
# S3_ENDPOINT_URL: usato dal backend/Celery (rete interna Docker, es. http://minio:9000).
# S3_PUBLIC_ENDPOINT_URL: host con cui il MOBILE raggiunge lo storage per i presigned URL
#   (in locale l'IP LAN del Mac; default = endpoint interno). In deploy coincidono.
S3_ENDPOINT_URL = os.getenv("S3_ENDPOINT_URL", os.getenv("S3_ENDPOINT", "http://minio:9000"))
S3_PUBLIC_ENDPOINT_URL = os.getenv(
    "S3_PUBLIC_ENDPOINT_URL",
    os.getenv("S3_PUBLIC_ENDPOINT", S3_ENDPOINT_URL),
)
S3_ACCESS_KEY_ID = os.getenv("S3_ACCESS_KEY_ID", "minioadmin")
S3_SECRET_ACCESS_KEY = os.getenv("S3_SECRET_ACCESS_KEY", "minioadmin")
S3_BUCKET_NAME = os.getenv("S3_BUCKET_NAME", os.getenv("S3_BUCKET", "mobility-trips"))
S3_REGION = os.getenv("S3_REGION", "us-east-1")
# Durata dei presigned URL (secondi).
S3_PRESIGN_EXPIRES_SECONDS = int(os.getenv("S3_PRESIGN_EXPIRES_SECONDS", "900"))
# Limite dimensione per singola parte caricata (byte). Default 25 MB.
INGESTION_MAX_PART_BYTES = int(os.getenv("INGESTION_MAX_PART_BYTES", str(25 * 1024 * 1024)))
# Limite del payload Core inline: il core deve restare piccolo e sincrono.
INGESTION_INLINE_CORE_MAX_BYTES = int(
    os.getenv("INGESTION_INLINE_CORE_MAX_BYTES", str(1 * 1024 * 1024))
)

# CONGELATO: la cancellazione dei blob raw dopo HAR e' predisposta ma disattivata
# finche' HAR non e' operativo (vedi REPORT D9). NON attivare senza HAR validato.
HAR_CLEANUP_ENABLED = env_bool("HAR_CLEANUP_ENABLED", False)
