# Report: Django Service Layer Architecture

## Decisione

Per il backend di Mobility Diary adottiamo una **Django Service Layer Architecture**.

Il pattern combina:

- **API layer**: route HTTP sottili.
- **Services**: operazioni di scrittura e workflow applicativi.
- **Selectors**: query di lettura e read-model complessi.
- **Domain modules**: logica pura, policy, trasformazioni e proiezioni.
- **Adapters**: integrazioni tecniche e formati esterni, come storage, gzip, binary codec, ML/HAR, Redis/SSE.
- **Task orchestrators**: task Celery sottili, che chiamano servizi/adapters invece di contenere business logic.

Questa scelta e' piu' adatta di una Clean Architecture pura per un progetto Django: rispetta Django ORM e Active Record, ma evita fat views, fat API e task Celery monolitici.

## Perche' Questo Pattern

Il backend attuale contiene molta logica nei punti di ingresso:

- `back-end/ninja/mobility/api.py`: molte route, query, analytics, reload, privacy, track.
- `back-end/ninja/mobility/ingestion/api.py`: workflow ingestion, start, heartbeat, inline core, multipart upload.
- `back-end/ninja/mobility/tasks.py`: parsing raw sensor, materializzazione GPS/transitions, path PostGIS, orchestrazione HAR.

Il problema non e' solo la lunghezza dei file. Il problema e' che API e task stanno facendo troppi mestieri:

- parlano HTTP;
- aprono transazioni;
- applicano regole di business;
- fanno query complesse;
- parsano formati binari;
- orchestrano task asincroni;
- materializzano il dominio.

Questo rende difficile:

- testare la logica senza passare da HTTP o Celery;
- capire dove cambiare una regola;
- riusare lo stesso workflow da API, task, command o test;
- evitare import incrociati fragili.

Esempi di odori attuali:

- `mobility/api.py` importa `_active_ingestions` da `ingestion.api`.
- `mobility/api.py` importa `_build_trip_path` da `tasks.py`.
- `replay_raw.py` importa `process_trip_har_final` da `tasks.py`.

Questi import indicano che alcune funzioni private sono diventate dipendenze applicative. Con la Service Layer Architecture, quelle funzioni devono vivere in moduli espliciti: services, selectors, materialization o adapters.

## Fonti e Riferimenti

### HackSoft Django Styleguide

Fonte: https://github.com/HackSoftware/Django-Styleguide

La Django Styleguide di HackSoft propone una struttura molto vicina a quella scelta:

- business logic in **Services**;
- query complesse in **Selectors**;
- API/views sottili;
- evitare di mettere business logic in API, serializers, forms, signals o manager generici.

La guida e' particolarmente adatta al nostro caso perche' non forza una Clean Architecture dogmatica. Propone invece una separazione pragmatica, testata in progetti Django reali.

### Django Design Philosophies

Fonte: https://docs.djangoproject.com/en/5.2/misc/design-philosophies/

La documentazione ufficiale Django dichiara principi coerenti con questa scelta:

- **loose coupling and tight cohesion**;
- **DRY**;
- **explicit is better than implicit**;
- modelli Django come Active Record;
- uso potente dell'ORM senza nasconderlo inutilmente.

Questo e' importante: una Repository Architecture pura sopra Django rischia di duplicare l'astrazione gia' fornita dall'ORM. Meglio usare ORM direttamente in services/selectors quando serve, mantenendo pero' API e task sottili.

### Cosmic Python: Service Layer

Fonte: https://www.cosmicpython.com/book/chapter_04_service_layer.html

Cosmic Python descrive il Service Layer come punto di ingresso dei casi d'uso applicativi. L'API deve occuparsi di HTTP; il service layer deve orchestrare il caso d'uso; la logica di dominio deve restare isolata.

Questo principio si applica bene a:

- start ingestion;
- heartbeat;
- stop/sync;
- inline core upload;
- replay;
- materializzazione Trip;
- final HAR processing.

### Cosmic Python: Repository Pattern

Fonte: https://www.cosmicpython.com/book/chapter_02_repository.html

Il Repository Pattern e' utile quando si vuole disaccoppiare fortemente il dominio dallo storage. Pero' introduce un costo: piu' astrazioni, piu' boilerplate, piu' layer da mantenere.

Nel nostro caso lo useremo solo se serve davvero una seconda implementazione o un fake stabile per test di dominio. Non creeremo repository generici per ogni model Django.

## Pattern Scelto

Nome operativo:

> **Django Service Layer Architecture**

Regola base:

```text
HTTP e Celery orchestrano.
Services cambiano stato.
Selectors leggono dati.
Domain modules calcolano regole pure.
Adapters parlano con infrastruttura/formati esterni.
```

## Struttura Target

Struttura proposta, incrementale:

```text
back-end/ninja/mobility/
  models.py
  schemas.py

  ingestion/
    api.py
    schemas.py
    services.py
    selectors.py
    materialization.py
    raw_sensor_codec.py
    storage.py
    tasks.py

  trips/
    api.py
    services.py
    selectors.py

  analytics/
    api.py
    selectors.py

  diary/
    projection.py
    export.py
    services.py

  places/
    services.py
    selectors.py

  jobs/
    ingestion_tasks.py
    har_tasks.py
    place_tasks.py
```

Non e' necessario arrivare subito a questa struttura completa. Il refactoring deve procedere per tagli piccoli e verificabili.

## Responsabilita' Dei Layer

### API Layer

File tipici:

- `api.py`
- `ingestion/api.py`
- futuri `trips/api.py`, `analytics/api.py`

Responsabilita':

- auth;
- parsing payload;
- conversione schema input -> command;
- chiamata al service/selector;
- mapping errori -> HTTP status;
- response schema.

Non deve contenere:

- transazioni complesse;
- bulk create;
- parsing gzip/binario;
- regole di active ingestion;
- query analytics complesse;
- logica HAR/replay.

### Services

Responsabilita':

- casi d'uso applicativi;
- transazioni;
- validazioni che attraversano piu' model;
- mutazioni DB;
- coordinamento tra moduli.

Esempi:

```python
start_recording(...)
heartbeat_recording(...)
abandon_recording(...)
ingest_inline_core(...)
complete_core_upload(...)
complete_raw_upload(...)
delete_trip(...)
reload_trip(...)
```

### Selectors

Responsabilita':

- query di lettura;
- annotazioni;
- prefetch/select_related;
- aggregazioni;
- read-model per API.

Esempi:

```python
trip_list_for_user(user_id)
trip_track(trip_id, user_id)
reload_slots_for_trip(...)
analytics_buckets(...)
active_ingestion_for_user(...)
```

### Domain Modules

Responsabilita':

- logica pura;
- policy;
- trasformazioni indipendenti da HTTP;
- funzioni testabili senza request e idealmente senza DB.

Gia' presenti:

- `privacy.py`
- `diary_projection.py`
- `diary_export.py`
- `significant_places.py`, almeno in parte.

### Adapters

Responsabilita':

- dettagli tecnici;
- storage object;
- gzip;
- parsing binary sensor format;
- ML/HAR model adapter;
- Redis/SSE.

Esempi:

```python
raw_sensor_codec.decode_sensor_windows(...)
storage.read_object(...)
har_adapter.predict_window_label(...)
diary_events.publish_diary_status(...)
```

### Celery Tasks

Responsabilita':

- retry;
- scheduling;
- lock/claim del job;
- chiamata a services/adapters;
- logging operativo.

Non devono contenere:

- parsing binario;
- materializzazione Trip;
- regole di business;
- query lunghe.

## Cosa Non Fare

### No Repository Generico Ovunque

Evitare:

```python
TripRepository.get_by_id(...)
TripRepository.save(...)
GpsPointRepository.bulk_create(...)
```

Se il repository e' solo un wrapper sottile del Django ORM, peggiora il codice.

Usare repository solo quando:

- serve davvero invertire la dipendenza;
- abbiamo due adapter reali;
- vogliamo testare un dominio puro senza Django;
- la complessita' nascosta dietro l'interfaccia e' significativa.

### No Service Monolitico

Evitare:

```python
class TripService:
    def start(...)
    def stop(...)
    def reload(...)
    def analytics(...)
    def privacy(...)
    def delete(...)
```

Meglio moduli focalizzati:

```python
ingestion/services.py
trips/services.py
analytics/selectors.py
```

### No Big Bang Refactor

Non riscrivere tutto insieme. Il backend fa ingestion, sync, HAR, privacy, analytics e replay: il rischio regressioni e' alto.

## Piano Di Refactoring

### Step 0: Baseline e Safety Net

Obiettivo: sapere se il refactoring rompe qualcosa.

Azioni:

1. Eseguire i test backend esistenti.
2. Identificare i test critici:
   - ingestion API;
   - inline core;
   - raw sensor upload;
   - HAR final;
   - replay;
   - diary privacy export;
   - analytics.
3. Aggiungere test mancanti solo dove il refactor tocchera' logica fragile.

Output:

- lista test baseline;
- eventuali test di regressione nuovi.

### Step 1: Estrarre Raw Sensor Codec

Obiettivo: togliere parsing tecnico da `tasks.py`.

Nuovo file:

```text
mobility/ingestion/raw_sensor_codec.py
```

Spostare:

- `_RAW_SENSOR_BINARY_MAGIC`
- `_RAW_SENSOR_BINARY_HEADER`
- `_RAW_SENSOR_BINARY_WINDOW_HEADER`
- `InvalidRawSensorPayload`
- `_datetime_from_epoch_micros`
- `_decode_binary_sensor_windows`
- `_parse_required_datetime`
- `_window_matrix`
- `_parse_sensor_window`
- parti di `_load_raw_sensor_part_windows` che riguardano decoding.

Interfaccia target:

```python
def decode_sensor_windows_payload(raw: bytes) -> list[PipelineSensorWindow]:
    ...
```

Effetto:

- `tasks.py` legge bytes da storage;
- `raw_sensor_codec.py` decide se binario o JSON legacy e restituisce finestre.

Test:

- payload binario valido;
- magic non valido;
- payload troncato;
- JSON legacy valido;
- timestamp invalido.

### Step 2: Estrarre Ingestion Materialization

Obiettivo: togliere da API/task la creazione di Trip, GPS, transitions e path.

Nuovo file:

```text
mobility/ingestion/materialization.py
```

Spostare:

- `_get_or_create_inline_trip`
- `_materialize_inline_core`
- `_materialize_gps`
- `_materialize_transitions`
- `_build_trip_path`
- `_distance_meters_from_postgis`

Interfacce target:

```python
def materialize_inline_core(ingestion, payload) -> MaterializedCoreResult:
    ...

def materialize_part_core(ingestion) -> MaterializedCoreResult:
    ...
```

Nota:

- `tasks.py` non deve piu' esportare `_build_trip_path`.
- `api.py` non deve importare funzioni private da `tasks.py`.

### Step 3: Estrarre Ingestion Selectors

Obiettivo: rimuovere query di active ingestion da `ingestion/api.py` quando sono usate da altri moduli.

Nuovo file:

```text
mobility/ingestion/selectors.py
```

Spostare:

- `_active_ingestions`
- `_active_last_seen`
- eventuali lookup per status/part state se usati fuori.

Interfacce target:

```python
def active_ingestions_for_user(user_id: int):
    ...

def active_ingestion_for_user(user_id: int) -> TripIngestion | None:
    ...
```

Effetto:

- `mobility/api.py` importa da `ingestion/selectors.py`, non da `ingestion/api.py`.

### Step 4: Estrarre Ingestion Services

Obiettivo: rendere `ingestion/api.py` un layer HTTP sottile.

Nuovo file:

```text
mobility/ingestion/services.py
```

Spostare workflow:

- start recording;
- heartbeat;
- abandon;
- inline core ingestion;
- multipart create/presign/confirm/complete;
- stale active ingestion policy;
- failed-final lock release.

Interfacce target indicative:

```python
def start_recording(*, user_id: int, command: StartRecordingCommand) -> StartRecordingResult:
    ...

def heartbeat_recording(*, user_id: int, ingestion_id: int, command: HeartbeatCommand) -> HeartbeatResult:
    ...

def abandon_recording(*, user_id: int, ingestion_id: int, device_id: str) -> AbandonResult:
    ...

def ingest_inline_core(*, user_id: int, payload: InlineCoreIn, body_size: int) -> InlineCoreResult:
    ...
```

Le route gestiscono solo:

- request/auth;
- schema input;
- try/except errori applicativi;
- schema output.

### Step 5: Estrarre Trip Selectors

Obiettivo: togliere read-model complessi da `mobility/api.py`.

Nuovo file:

```text
mobility/trips/selectors.py
```

Spostare:

- `_trip_list_items`
- `_trip_list_annotations`
- `_has_track_case`
- `_trip_list_item`
- `_trip_list_item_by_id`
- track query;
- reloadable list.

Interfacce target:

```python
def trip_list_for_user(user_id: int) -> list[dict]:
    ...

def trip_list_item_for_user(*, user_id: int, trip_id: int) -> dict:
    ...

def trip_track_for_user(*, user_id: int, trip_id: int) -> TrackDTO:
    ...
```

### Step 6: Estrarre Trip Services

Obiettivo: separare mutazioni sui viaggi.

Nuovo file:

```text
mobility/trips/services.py
```

Spostare:

- delete trip;
- update note;
- toggle reloadable;
- close legacy trip, se ancora necessario;
- reload trip workflow, o parte di esso.

### Step 7: Estrarre Analytics Selectors

Obiettivo: isolare query e aggregazioni analytics.

Nuovo file:

```text
mobility/analytics/selectors.py
```

Spostare:

- `_analytics_zone`
- `_analytics_buckets`
- `_analytics_heatmap`
- `_weekly_heatmaps`
- `_prevalent_mode`
- `_frequent_routes`

Lasciare in API solo:

```python
@router.get("/analytics")
def get_personal_analytics(...):
    return analytics_selectors.personal_analytics(...)
```

### Step 8: Snellire Celery Tasks

Obiettivo: `tasks.py` diventa orchestratore.

Possibile nuova struttura:

```text
mobility/jobs/ingestion_tasks.py
mobility/jobs/har_tasks.py
mobility/jobs/place_tasks.py
```

Ogni task:

- carica job/ingestion;
- chiama service/materialization/codec;
- gestisce retry;
- aggiorna status operativo.

### Step 9: Stabilizzare Errori Applicativi

Obiettivo: evitare che services lancino direttamente `HttpError` ovunque.

Nuovo file possibile:

```text
mobility/errors.py
```

Esempi:

```python
class ApplicationError(Exception):
    status_code = 400

class ConflictError(ApplicationError):
    status_code = 409

class NotFoundError(ApplicationError):
    status_code = 404
```

Le API trasformano errori applicativi in HTTP. I task possono gestirli in modo diverso.

### Step 10: Documentare Le Regole Architetturali

Aggiornare `CONTEXT.md` o creare un ADR:

```text
docs/adr/ADR_BACKEND_DJANGO_SERVICE_LAYER.md
```

Regole:

- API non importa da `tasks.py`.
- API non importa funzioni private da altre API.
- Task non parsano formati binari.
- Query di lettura complesse stanno in selectors.
- Mutazioni stanno in services.
- Logica pura sta in domain modules.
- Repository solo se c'e' un motivo reale.

## Ordine Raccomandato

Sequenza a basso rischio:

1. `raw_sensor_codec.py`
2. `ingestion/materialization.py`
3. `ingestion/selectors.py`
4. `ingestion/services.py`
5. `trips/selectors.py`
6. `trips/services.py`
7. `analytics/selectors.py`
8. split Celery tasks
9. error model applicativo
10. ADR/regole architetturali

## Criteri Di Successo

Il refactoring e' riuscito se:

- `api.py` e `ingestion/api.py` diventano route sottili;
- `tasks.py` non contiene piu' parsing raw sensor;
- non ci sono import da funzioni private di API/task;
- i workflow principali sono testabili chiamando services;
- le query complesse sono testabili chiamando selectors;
- i test backend esistenti continuano a passare;
- ogni step puo' essere rilasciato senza big bang.

## Raccomandazione Finale

Adottare ufficialmente:

> **Django Service Layer Architecture**

con questa formulazione:

> Il backend usa Services per i comandi e i workflow applicativi, Selectors per le query di lettura, Domain Modules per le regole pure e Adapters per infrastruttura/formati esterni. API e Celery task restano layer di orchestrazione sottile.

Questa scelta e' abbastanza precisa da guidare il refactoring, ma abbastanza Django-native da non introdurre astrazioni inutili.
