# Report Divisione Backend

Questo report descrive solo il backend del progetto Mobility Diary. L'obiettivo e' spiegare come e' diviso Django Ninja, perche' esistono solo due app Django principali e cosa contiene ogni area.

## 1. Idea generale

Il backend si trova in:

```text
back-end/ninja/
```

La struttura principale e':

```text
back-end/ninja/
├── manage.py
├── config/
├── accounts/
├── mobility/
├── manual_har/
├── requirements.txt
├── Dockerfile
└── pytest.ini
```

La divisione concettuale e':

```text
config   = configurazione tecnica del progetto Django
accounts = dominio utenti, autenticazione e privacy
mobility = dominio principale: viaggi, diario, ingestion, ML, luoghi, analytics
```

Il backend non e' diviso in tante app Django piccole. Usa poche app Django grandi, poi divide la complessita' dentro l'app con moduli specializzati: `api`, `models`, `schemas`, `services`, `selectors`, `tasks`, `ingestion`, `ml`.

## 2. Perche' solo due app Django

Nel progetto ci sono due app applicative:

```text
accounts
mobility
```

Questa scelta ha senso perche' le app Django rappresentano macro-domini:

```text
accounts -> chi e' l'utente e come si autentica
mobility -> cosa fa l'utente nei suoi viaggi
```

Ingestion, ML, analytics, luoghi e route assistant non sono app Django autonome perche' non sono prodotti separati: sono capacita' interne del dominio `mobility`.

La frase da usare per spiegarlo:

> Il backend usa poche app Django per rappresentare i domini principali. La complessita' interna viene separata con una service layer architecture: gli endpoint Ninja restano sottili, i modelli rappresentano il database, e la logica applicativa vive in servizi, selectors, task e moduli di dominio.

## 3. `manage.py`

File standard Django.

Serve per eseguire comandi da terminale:

```text
python manage.py migrate
python manage.py runserver
python manage.py createsuperuser
python manage.py shell
```

Non contiene logica applicativa. E' solo il punto di ingresso per i comandi Django.

## 4. Cartella `config`

La cartella:

```text
back-end/ninja/config/
```

contiene la configurazione globale del progetto.

```text
config/
├── settings.py
├── urls.py
├── asgi.py
├── wsgi.py
├── celery.py
└── __init__.py
```

## 5. `config/settings.py`

Questo file contiene le impostazioni generali del backend.

Responsabilita' principali:

- leggere variabili d'ambiente;
- configurare database PostGIS;
- dichiarare app installate;
- configurare middleware;
- configurare CORS e CSRF;
- configurare cookie;
- configurare static files;
- configurare Redis e Celery;
- configurare MinIO/S3;
- configurare percorsi dei modelli HAR.

Dentro `INSTALLED_APPS` ci sono sia app Django standard sia app del progetto:

```python
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
```

Quindi Django carica:

```text
admin/auth/session/static/GIS -> funzionalita' Django
accounts/mobility             -> codice applicativo del progetto
```

## 6. `config/urls.py`

Questo e' il router principale del backend.

Contiene:

```python
api = NinjaAPI(title="Mobility Diary API")
api.add_router("/auth/", auth_router)
api.add_router("/privacy/", privacy_router)
api.add_router("/web/auth/", web_auth_router)
api.add_router("/web/", web_users_router)
api.add_router("/mobility/", mobility_router)
api.add_router("/ingestion/", ingestion_router)
```

Significa:

```text
/api/auth/       -> API autenticazione mobile
/api/privacy/    -> API privacy utente
/api/web/auth/   -> API autenticazione frontend web
/api/web/        -> API utenti lato web/admin dashboard
/api/mobility/   -> API viaggi, diario, luoghi, analytics
/api/ingestion/  -> API ingestione asincrona dei viaggi
```

Poi:

```python
urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/", api.urls),
]
```

Significa:

```text
/admin/ -> pannello Django admin
/api/   -> tutte le API Django Ninja
```

## 7. `config/asgi.py` e `config/wsgi.py`

Entrambi sono file standard creati nei progetti Django.

`asgi.py` espone l'app Django in formato ASGI.

Nel deploy attuale viene usato davvero, perche' il container web parte con:

```text
gunicorn config.asgi:application -k uvicorn.workers.UvicornWorker
```

Quindi la produzione carica:

```text
config.asgi:application
```

`wsgi.py` espone l'app Django in formato WSGI. Nel deploy attuale non e' il punto di ingresso usato, ma viene lasciato per compatibilita' con deploy WSGI classici.

## 8. `config/celery.py`

Configura Celery.

```python
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
app = Celery("mobility_diary")
app.config_from_object("django.conf:settings", namespace="CELERY")
app.autodiscover_tasks()
```

Significa:

1. Celery usa gli stessi settings di Django.
2. Viene creata l'app Celery chiamata `mobility_diary`.
3. Celery legge le impostazioni che iniziano con `CELERY_`.
4. Celery cerca automaticamente file `tasks.py` nelle app Django.

Nel progetto questo serve soprattutto per processare lavori asincroni di `mobility`, per esempio ingestion, ricalcoli e mining.

## 9. App `accounts`

La cartella:

```text
back-end/ninja/accounts/
```

gestisce identita', autenticazione, token e privacy utente.

Struttura:

```text
accounts/
├── models.py
├── api.py
├── web_api.py
├── web_auth.py
├── web_users_api.py
├── privacy_api.py
├── auth.py
├── schemas.py
├── session_cache.py
├── admin.py
├── apps.py
└── migrations/
```

## 10. `accounts/models.py`

Contiene i modelli database del dominio accounts.

### `AccessToken`

Token usato dal mobile.

Serve a:

- associare un token a un utente;
- salvare solo l'hash del token;
- gestire scadenza;
- gestire revoca;
- tracciare device e user agent.

Metodi importanti:

```python
hash_raw_token()
issue_for_user()
is_valid
revoke()
```

### `UserPrivacySettings`

Impostazioni privacy dell'utente.

Livelli:

```text
precise
approximate
aggregated
```

Campi importanti:

```text
user
level
is_first_login
created_at
updated_at
```

### `WebRefreshToken`

Refresh token per il frontend web.

Serve a:

- mantenere sessione web;
- ruotare token;
- revocare token;
- limitare accesso a staff/superuser.

## 11. File API di `accounts`

### `accounts/api.py`

Router autenticazione mobile.

Collegato a:

```text
/api/auth/
```

### `accounts/privacy_api.py`

Router privacy.

Collegato a:

```text
/api/privacy/
```

### `accounts/web_api.py`

Router autenticazione web.

Collegato a:

```text
/api/web/auth/
```

### `accounts/web_users_api.py`

Router per utenti lato web.

Collegato a:

```text
/api/web/
```

### `accounts/auth.py`

Contiene funzioni/classi di autenticazione custom usate dagli endpoint.

### `accounts/web_auth.py`

Contiene logica specifica dei token web: creazione, refresh, verifica, revoca.

### `accounts/schemas.py`

Contiene gli schemi input/output per Django Ninja.

Regola importante:

```text
models.py  -> struttura database
schemas.py -> struttura JSON API
```

## 12. App `mobility`

La cartella:

```text
back-end/ninja/mobility/
```

e' il dominio principale del progetto.

Contiene:

- viaggi;
- punti GPS;
- transizioni della macchina a stati;
- finestre sensori;
- ingestion asincrona;
- classificazione HAR;
- segmenti del diario;
- luoghi abituali;
- analytics;
- export/privacy;
- task Celery.

Struttura:

```text
mobility/
├── models.py
├── api.py
├── schemas.py
├── tasks.py
├── privacy.py
├── diary_projection.py
├── diary_events.py
├── diary_export.py
├── geo.py
├── significant_places.py
├── replay_raw.py
├── ingestion/
├── ml/
├── services/
├── selectors/
├── management/
├── admin.py
├── apps.py
└── migrations/
```

## 13. `mobility/models.py`

Contiene le tabelle principali del dominio mobilita'.

### `Trip`

Rappresenta un viaggio.

Campi importanti:

```text
user
client_session_id
device_id
status
path
distance_meters
started_at
ended_at
```

Usa PostGIS per salvare `path` come linea geografica.

### `GpsPoint`

Rappresenta un punto GPS del viaggio.

Campi:

```text
trip
timestamp
point
speed_mps
accuracy_meters
```

### `StateTransition`

Rappresenta un cambio stato della FSM mobile.

Esempio:

```text
IDLE -> MOVING
MOVING -> STOPPED
```

### `SensorWindow`

Rappresenta una finestra di dati sensori.

Serve per la classificazione HAR.

Puo' contenere:

- matrice JSON;
- oppure riferimento a oggetto salvato su MinIO/S3.

### `MobilitySegment`

Rappresenta una riga del diario.

Tipi:

```text
STOP
MOVE
```

### `HabitualPlace`

Luogo abituale dell'utente.

Esempi:

```text
casa
universita
lavoro
palestra
altro
```

### `CandidateVisit`

Visita candidata calcolata dai dati GPS.

Serve come evidenza per costruire un `HabitualPlace`.

### `PlaceMiningStatus`

Stato del processo di mining dei luoghi.

Esempi:

```text
PENDING
RUNNING
SUCCEEDED
FAILED
```

### `TripIngestion` e `TripIngestionPart`

Modelli che tracciano l'ingestion asincrona:

- stato ingestion;
- parti caricate;
- errori;
- idempotenza;
- collegamento al viaggio finale.

## 14. `mobility/api.py`

Router principale della mobilita'.

Collegato a:

```text
/api/mobility/
```

Espone endpoint per:

- health check;
- lista viaggi;
- dettaglio viaggio;
- traccia GPS;
- diario;
- analytics;
- luoghi;
- route assistant;
- reload.

Questo file e' lo strato HTTP. Non dovrebbe contenere troppa business logic: riceve request, valida input, chiama selectors/services e restituisce JSON.

## 15. `mobility/schemas.py`

Schemi input/output delle API mobility.

Servono per definire i payload JSON senza esporre direttamente i modelli Django.

## 16. `mobility/tasks.py`

Task Celery del dominio mobility.

Responsabilita':

- eseguire lavori lunghi fuori dalla richiesta HTTP;
- processare ingestion;
- fare ricalcoli;
- eseguire mining luoghi;
- aggiornare proiezioni/segmenti.

## 17. File di dominio in `mobility`

### `privacy.py`

Contiene regole per trasformare i dati in base al livello privacy.

### `diary_projection.py`

Costruisce una vista leggibile del diario a partire dai dati persistenti.

Il concetto chiave:

```text
dati grezzi / segmenti / luoghi -> rappresentazione pronta per API/UI
```

### `diary_events.py`

Gestisce eventi collegati al diario.

### `diary_export.py`

Contiene logica di export dei dati del diario.

### `geo.py`

Funzioni geografiche di supporto.

### `significant_places.py`

Logica per individuare luoghi significativi/abituali.

### `replay_raw.py`

Logica per rigiocare dati raw o ricostruire elaborazioni.

## 18. Sotto-dominio `mobility/ingestion`

Cartella:

```text
mobility/ingestion/
```

Struttura:

```text
ingestion/
├── api.py
├── schemas.py
├── services.py
├── selectors.py
├── storage.py
├── raw_sensor_codec.py
├── raw_sensor_loader.py
├── materialization.py
└── __init__.py
```

Responsabilita' generale:

```text
ricevere dati viaggio dal mobile
-> salvare core viaggio
-> gestire upload sensor windows
-> processare dati
-> creare Trip/GpsPoint/StateTransition/SensorWindow
```

### `ingestion/api.py`

Endpoint HTTP dell'ingestion.

Collegato a:

```text
/api/ingestion/
```

### `ingestion/schemas.py`

Schemi input/output specifici dell'ingestion.

### `ingestion/services.py`

Logica applicativa dell'ingestion.

Qui stanno le operazioni che cambiano lo stato del sistema.

### `ingestion/selectors.py`

Query di lettura dell'ingestion.

### `ingestion/storage.py`

Adattatore verso MinIO/S3.

Serve per:

- generare presigned URL;
- controllare parti caricate;
- leggere oggetti;
- astrarre il client S3.

### `ingestion/raw_sensor_codec.py`

Codifica/decodifica dei payload raw sensori.

### `ingestion/raw_sensor_loader.py`

Carica dati raw sensori dallo storage.

### `ingestion/materialization.py`

Trasforma payload ingestion in modelli Django.

Esempio:

```text
payload core -> Trip + GpsPoint + StateTransition
payload raw  -> SensorWindow
```

## 19. Sotto-dominio `mobility/ml`

Cartella:

```text
mobility/ml/
```

Struttura:

```text
ml/
├── classifier.py
├── har_adapter.py
├── pipeline.py
├── preprocessing.py
├── label_map.json
├── norm_stats.json
└── __init__.py
```

Responsabilita':

```text
dati sensori -> preprocessing -> modello HAR -> label attivita'
```

### `classifier.py`

Coordina la classificazione.

### `har_adapter.py`

Adatta il modello Keras al resto del backend.

### `pipeline.py`

Pipeline completa di classificazione.

### `preprocessing.py`

Prepara dati numerici prima del modello.

### `label_map.json`

Mappa classi del modello in etichette.

### `norm_stats.json`

Statistiche di normalizzazione.

## 20. Cartella `mobility/services`

Struttura:

```text
services/
├── trips.py
├── places.py
├── har.py
├── route_assistant.py
├── reload.py
└── __init__.py
```

I services contengono casi d'uso e operazioni che modificano il sistema.

Regola:

```text
endpoint API -> chiama service
service      -> coordina models, selectors, task, storage, ML
```

### `services/trips.py`

Operazioni sui viaggi.

### `services/places.py`

Operazioni sui luoghi abituali.

### `services/har.py`

Operazioni legate alla classificazione HAR.

### `services/route_assistant.py`

Logica dell'assistente di percorso.

### `services/reload.py`

Rielaborazione/reload di viaggi.

## 21. Cartella `mobility/selectors`

Struttura:

```text
selectors/
├── trips.py
├── analytics.py
├── places.py
└── __init__.py
```

I selectors contengono query e letture.

Differenza chiave:

```text
services  -> scrivono o modificano stato
selectors -> leggono e preparano dati
```

### `selectors/trips.py`

Query su viaggi e tracce.

### `selectors/analytics.py`

Query e aggregazioni per dashboard/statistiche.

### `selectors/places.py`

Query sui luoghi abituali.

## 22. `admin.py`, `apps.py`, `migrations`

### `admin.py`

Registra modelli nel pannello Django admin.

### `apps.py`

Configurazione standard dell'app Django.

### `migrations/`

Storico delle modifiche allo schema database.

Non rappresentano logica applicativa: rappresentano evoluzione del database.

## 23. `manual_har`

Cartella:

```text
back-end/ninja/manual_har/
```

Contiene i modelli Keras usati per HAR:

```text
shl_cnn1d_full_100pct_5class_best.keras
shl_6ch_5class_gru_best.keras
```

Sono caricati dal backend tramite i path definiti in `settings.py`.

## 24. Backend infrastructure collegata

Anche se non e' codice Django, questa parte serve a capire come gira il backend.

File principale:

```text
docker-compose.coolify.yml
```

Servizi:

```text
gateway    -> Nginx
web        -> Django ASGI
worker     -> Celery worker
beat       -> Celery beat
migrate    -> migrazioni Django
redis      -> broker Celery
db         -> PostgreSQL/PostGIS
minio      -> storage S3 compatibile
minio-init -> crea bucket MinIO
```

Il container web usa:

```text
gunicorn config.asgi:application -k uvicorn.workers.UvicornWorker
```

Quindi in produzione il backend Django gira tramite ASGI.

## 25. Flusso principale backend

### Richiesta normale

```text
client
-> Nginx
-> Django Ninja endpoint
-> auth
-> schema input
-> selector/service
-> models/database
-> schema output
-> JSON response
```

### Ingestion viaggio

```text
mobile
-> /api/ingestion/
-> ingestion/api.py
-> ingestion/services.py
-> ingestion/storage.py per MinIO
-> Celery task
-> ingestion/materialization.py
-> mobility/models.py
```

### Classificazione HAR

```text
SensorWindow
-> raw_sensor_loader / preprocessing
-> ml/pipeline.py
-> ml/har_adapter.py
-> modello Keras
-> activity label
-> segmenti diario
```

## 26. Regola mentale finale

Per spiegare il backend, usa questa mappa:

```text
config      = configurazione e ingressi tecnici
accounts    = utente, token, privacy
mobility    = dominio viaggi
models      = database
schemas     = JSON API
api         = endpoint HTTP
services    = operazioni/casi d'uso
selectors   = query/letture
tasks       = asincrono Celery
ingestion   = entrata dati dal mobile
ml          = classificazione sensori
infra       = Nginx, PostGIS, Redis, MinIO
```

Frase conclusiva:

> Il backend e' organizzato in due macro-domini Django, `accounts` e `mobility`. `accounts` gestisce identita', autenticazione e privacy; `mobility` gestisce il dominio principale dei viaggi. La complessita' non viene spezzata creando molte app Django, ma separando internamente le responsabilita' in API, modelli, schemi, servizi, selectors, task asincroni, ingestion e ML.
