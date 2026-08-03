import os
from pathlib import Path

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
ENV_FILE = os.getenv("DJANGO_ENV_FILE")
if ENV_FILE:
    load_dotenv(BASE_DIR / ENV_FILE)
else:
    load_dotenv(BASE_DIR / ".env.local")

# funzioni helper per leggere variabili d'ambiente e transformale in booleano o lista
def env_bool(name: str, default: bool = False) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.lower() in {"True", "true", "1", "yes"}


def env_list(name: str, default: str = "") -> list[str]:
    raw_value = os.getenv(name, default)
    return [item.strip() for item in raw_value.split(",") if item.strip()]


# restituisce solo il dominio -> server per gli allowed host di django
def normalize_host(host: str) -> str:
    return host.removeprefix("https://").removeprefix("http://").split("/")[0]

# restuisce il dominio + https
def normalize_csrf_origin(origin: str) -> str:
    if origin.startswith(("http://", "https://")):
        return origin.rstrip("/")
    return f"https://{origin.rstrip('/')}"



SECRET_KEY = os.getenv("DJANGO_SECRET_KEY", "unsafe-dev-secret-key")

DEBUG = env_bool("DJANGO_DEBUG", True)
ALLOWED_HOSTS = (
    [
        normalize_host(host)
        for host in env_list("DJANGO_ALLOWED_HOSTS", "localhost,127.0.0.1")
        
    ]
)
CSRF_TRUSTED_ORIGINS = (
    [
        normalize_csrf_origin(origin)
        for origin in env_list("CSRF_TRUSTED_ORIGINS")
    ]
)
CORS_ALLOWED_ORIGINS = (
    [
        normalize_csrf_origin(origin)
        for origin in env_list("CORS_ALLOWED_ORIGINS")
    ]
)

INSTALLED_APPS = [
    "corsheaders",
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
    "corsheaders.middleware.CorsMiddleware",
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
        "DISABLE_SERVER_SIDE_CURSORS": env_bool(
            "POSTGRES_DISABLE_SERVER_SIDE_CURSORS",
            False,
        ),
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

#Parametri per Django <-> Nginx
# Se la richiesta che arriva ha come header HTTP_X_FORWARDED_PROTO considerala HTTPS, quindi valida 
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
# Serve a django per capire il vero dominio della richiesta, essendo esso dentro Nginx
USE_X_FORWARDED_HOST = env_bool("USE_X_FORWARDED_HOST", True)


SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SAMESITE = "Lax"
SESSION_COOKIE_SECURE = env_bool("SESSION_COOKIE_SECURE", not DEBUG)
CSRF_COOKIE_HTTPONLY = False
CSRF_COOKIE_SAMESITE = "Lax"
CSRF_COOKIE_SECURE = env_bool("CSRF_COOKIE_SECURE", not DEBUG)
MOBILE_ACCESS_TOKEN_TTL_DAYS = 30
WEB_ACCESS_TOKEN_TTL_MINUTES = int(os.getenv("WEB_ACCESS_TOKEN_TTL_MINUTES", "15"))
WEB_REFRESH_TOKEN_TTL_DAYS = int(os.getenv("WEB_REFRESH_TOKEN_TTL_DAYS", "7"))


#Sezione Redis + Celery

REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6381/0")
CELERY_BROKER_URL = os.getenv("CELERY_BROKER_URL", REDIS_URL)
CELERY_RESULT_BACKEND = os.getenv("CELERY_RESULT_BACKEND", "redis://localhost:6381/1")
CELERY_TASK_TRACK_STARTED = True
CELERY_TASK_TIME_LIMIT = 30 * 60

# Sezione S3
#Endpoint interno per tutti i servizi che devono accederci
S3_ENDPOINT_URL = os.getenv("S3_ENDPOINT_URL", "http://minio:9000")
#Endpoint pubblico che il mobile deve poter raggiungere
S3_PUBLIC_ENDPOINT_URL = os.getenv(
    "S3_PUBLIC_ENDPOINT_URL",
   S3_ENDPOINT_URL,
)
S3_ACCESS_KEY_ID = os.getenv("S3_ACCESS_KEY_ID", "minioadmin")
S3_SECRET_ACCESS_KEY = os.getenv("S3_SECRET_ACCESS_KEY", "minioadmin")
S3_BUCKET_NAME = os.getenv("S3_BUCKET_NAME", os.getenv("S3_BUCKET", "mobility-trips"))
S3_REGION = os.getenv("S3_REGION", "us-east-1")
S3_PRESIGN_EXPIRES_SECONDS = int("900")
INGESTION_MAX_PART_BYTES = int(25 * 1024 * 1024) #25 mb
RAW_SENSOR_COPY_FORMAT = os.getenv("RAW_SENSOR_COPY_FORMAT", "binary")


#Sezione HAR
HAR_CNN_MODEL_PATH = str(BASE_DIR / "manual_har" / "shl_cnn1d_full_100pct_5class_best.keras")
HAR_GRU_MODEL_PATH = str(BASE_DIR / "manual_har" / "shl_6ch_5class_gru_best.keras")
HAR_GRU_SEQUENCE_LENGTH = 32
HAR_WINDOW_SAMPLE_COUNT = 500
