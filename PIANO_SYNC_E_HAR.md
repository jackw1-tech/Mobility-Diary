# Piano di Implementazione: SyncService Mobile → Backend + Pipeline HAR

Questo documento consolida le decisioni prese nella sessione di design e definisce il
piano concreto per il **prossimo feature**: la sincronizzazione differita dei dati di
viaggio dal mobile al backend, e l'elaborazione asincrona che produce il diario della
mobilità (segmenti + luoghi significativi) tramite HAR.

Riferimenti: [INTEGRAZIONE_FSM_HAR.md](INTEGRAZIONE_FSM_HAR.md),
[REPORT_FRONTEND_ATTUALE.md](REPORT_FRONTEND_ATTUALE.md),
[REPORT_ARCHITETTURA_BACKEND_LIVE.md](REPORT_ARCHITETTURA_BACKEND_LIVE.md),
[AUTHENTICATION_REPORT.md](AUTHENTICATION_REPORT.md), e la traccia di progetto
(Proposta 2 – Privacy-Aware Mobility Diary con HAR).

---

## 1. Obiettivo e scope

### In scope

```
Mobile: SyncService che riconcilia SQLite → backend a fine viaggio (deferred, non-live)
Backend: ricezione dati + worker Celery che normalizza, fa girare CNN+GRU,
         corregge con GPS, segmenta e scrive il diario
```

### Fuori scope (feature successive, da grigliare a parte)

```
- privacy: vista precisa vs approssimata/aggregata (+3pt)
- dashboard web
- UI diario lato mobile
- sync in background OS (WorkManager / BGTaskScheduler)
- acquisizione sensori in background (lavoro separato, obbligatorio in futuro)
- chiusura automatica del viaggio da parte dell'FSM
- luoghi ricorrenti cross-viaggio (+2pt, ST_ClusterDBSCAN)
- inferenza live / servizio FastAPI separato
```

---

## 2. Registro delle decisioni

| # | Decisione | Scelta |
|---|-----------|--------|
| 1 | Modello di sync | Deferred / batch a fine viaggio (non-live). HAR gira una volta, a fine viaggio (GRU) |
| 2 | Dove vivono i dati | Matrici sensori in **Postgres** (JSONField); in **Redis** solo il `job_id` |
| 3 | Creazione Trip | Eager allo Start (anche vuoto), ma Start **mai bloccante** (local-first ottimistico) |
| 4 | Idempotenza Trip | Chiave = **UUID di sessione locale** → backend `get_or_create(client_session_id)` |
| 5 | Esecuzione sync | **SyncService** che riconcilia SQLite→backend. Tenta allo Stop; fallback foreground-only |
| 6 | Ordine di sync | crea Trip → GPS → finestre → chiudi Trip → `process-har` (gated alla fine) |
| 7 | Chiusura viaggio | Solo il bottone **Stop** (FSM auto-close = futuro) |
| 8 | StateTransitions | **Sincronizzate** (scheletro della segmentazione del diario) |
| 9 | Idle / fermo | **Opzione 2**: CNN/GRU sui viaggi; soste lunghe = idle da FSM+GPS; un solo `ActivityLabel.idle` |
| 10 | Dove gira il modello | **Worker Celery** in `ninja` (no FastAPI). TensorFlow solo nell'immagine worker |
| 11 | Correzione GPS | Fusione velocità GPS nel worker per sciogliere **IDLE↔MOVING_VEHICLE** |
| 12 | Normalizzazione | Mobile manda matrice **grezza** `500×9`; normalizza il **worker** con `norm_stats.json` |
| 13 | Elaborazione | **Asincrona** (Celery): l'upload risponde subito; inferenza nel worker, modello caldo |
| 14 | Recupero risultato | Mobile fa **polling** dello stato finché Trip = `PROCESSED` |
| 15 | Sosta / luogo | Blocco `STATIONARY` **≥ 5 min** entro **~50–100 m** → un luogo (centroide) |
| 16 | Modello diario | `Trip`(=MobilityTrace) + nuove `MobilitySegment` e `SignificantPlace`; `ActivityLabel` = enum sul segmento |
| 17 | PostGIS | **GeoDjango abilitato** (PointField, GDAL nell'immagine); DBSCAN futuro via RawSQL |

---

## 3. Flusso end-to-end

```
                         MOBILE
  Start ─► crea sessione SQLite (UUID) ─► [tenta POST /trips]  (non bloccante)
  ...tracking... ─► SQLite: GpsPoints, SensorWindows, StateTransitions (isSynced=false)
  Stop  ─► chiude sessione locale ─► nudge SyncService

                      SYNC SERVICE (riconciliatore)
  per ogni sessione non sincronizzata:
    1. POST /trips (idempotente, client_session_id=UUID) → salva remoteTripId
    2. POST /gps-points        (a chunk, marca isSynced per riga)
    3. POST /sensor-windows    (a chunk, marca isSynced per riga)
    4. POST /state-transitions (batch)
    5. POST /trips/{id}/close  (status=CLOSED, ended_at)
    6. POST /trips/{id}/process-har   ← solo quando 1–5 completati

                         BACKEND (HTTP)
  endpoint = scrivono in Postgres e rispondono SUBITO (no inferenza)
  process-har = mette job_id in Redis

                      WORKER CELERY (async)
  legge finestre da Postgres ─► normalizza (norm_stats) ─► CNN → embedding 128
   ─► GRU su sequenze di 64 (fallback se < 64) ─► fusione velocità GPS (IDLE↔veicolo)
   ─► segmentazione 2 passate ─► luoghi significativi (PostGIS)
   ─► scrive MobilitySegment + SignificantPlace ─► Trip.status = PROCESSED

                         MOBILE
  polling stato Trip ─► quando PROCESSED ─► GET diario ─► mostra
```

---

## 4. Backend

### 4.1 Abilitare PostGIS + GeoDjango

- `requirements.txt`: aggiungere il supporto GIS (Django GIS è incluso, servono le **librerie di
  sistema** GDAL/GEOS/PROJ nell'immagine).
- `Dockerfile` (web **e** worker): installare `binutils libproj-dev gdal-bin libgdal-dev libgeos-dev`
  (o impostare `GDAL_LIBRARY_PATH`/`GEOS_LIBRARY_PATH`).
- `config/settings.py`:
  - `INSTALLED_APPS += ['django.contrib.gis']`
  - `DATABASES['default']['ENGINE'] = 'django.contrib.gis.db.backends.postgis'`
- Migration iniziale: `migrations.RunSQL("CREATE EXTENSION IF NOT EXISTS postgis;")`.

### 4.2 Modelli (`mobility/models.py`)

```
Trip (= MobilityTrace)               [esistente, da estendere]
  + client_session_id  CharField(unique)   ← idempotency key (UUID dal mobile)
  status, ended_at                          già presenti (OPEN/CLOSED/PROCESSED)

GpsPoint                              [da migrare a GIS]
  point = PointField(geography=True)        ← sostituisce latitude/longitude Decimal
  + UniqueConstraint(trip, timestamp)       ← anti-duplicato su retry

SensorWindow                          [ok, già pronto]
  matrix JSONField · is_synced · UniqueConstraint(trip, start, end)

StateTransition                       [NUOVO modello]
  trip_fk, from_state, to_state, reason, timestamp, sigma, speed_mps

MobilitySegment                       [NUOVO – riga del diario]
  trip_fk, start, end, kind (STOP|MOVE), activity_label (enum), place_fk (nullable)

SignificantPlace                      [NUOVO]
  trip_fk, center = PointField, radius_m, dwell_seconds, label (nullable)
```

`ActivityLabel` = enum `IDLE/WALKING/RUNNING/BIKING/MOVING_VEHICLE` come **campo** del segmento,
non tabella a sé.

### 4.3 API (`mobility/api.py`, `mobility/schemas.py`)

- `create_trip`: passare a `Trip.objects.get_or_create(user, client_session_id=...)`.
- `add_gps_point` / batch: schema Ninja con `lat`/`lon` → costruire `Point(lon, lat, srid=4326)`.
- `add_sensor_windows`: `bulk_create(..., ignore_conflicts=True)`.
- **Nuovo** `add_state_transitions` (batch).
- **Nuovo** `close_trip` → `status=CLOSED`, `ended_at=now`.
- `enqueue_har_job` (process-har): invariato, ma il mobile lo chiama **solo dopo** che tutto è sincronizzato.
- **Nuovo** `get_trip_diary` → ritorna stato + segmenti + luoghi (per polling e fetch).
- Serializzazione `PointField ↔ {lat, lon}` a mano negli schemi.

### 4.4 Worker (`mobility/tasks.py`)

- **Artefatti** versionati nel backend (oggi solo su SSD esterno):
  `shl_9ch_5class_best.keras` (CNN, 23MB), `shl_9ch_5class_gru_best.keras` (GRU, 921KB),
  `norm_stats.json`, `label_map.json`. → Git LFS o volume montato.
- `requirements-worker.txt`: **TensorFlow** (solo immagine worker).
- Caricare CNN + GRU **una volta** all'avvio del worker (warm in RAM).
- `process_trip_har(job_id)`:

```python
1. windows = finestre del Trip da Postgres, ORDINATE per start_timestamp
2. per ogni finestra: normalizza 500×9 con norm_stats (mean/std) + imputa NaN
3. emb = CNN.extractor(windows)                 # embedding 128 per finestra
4. labels = GRU su sequenze di 64 (L=64)        # fallback CNN/smoothing se < 64 finestre
5. labels = correct_idle_with_gps(labels, gps)  # fusione velocità GPS (IDLE↔veicolo)
6. segmenti = segmentazione_2_passate(transizioni_FSM, labels)
       passata 1: confini STOP/MOVE dalle StateTransitions
       passata 2: dentro i MOVE, split a ogni cambio di label HAR
7. luoghi  = per ogni STOP ≥ 5 min: centroide GPS via PostGIS (ST_Centroid)
8. scrivi MobilitySegment + SignificantPlace
9. Trip.status = PROCESSED   (guard di idempotenza: se già PROCESSED, esci)
```

Correzione GPS (riferimento, da tarare):

```python
VEHICLE_SPEED_MPS = 8.0    # ~29 km/h: chiaramente un veicolo
CONTEXT = 6                # ±6 finestre = ±30s

def correct_idle_with_gps(windows, gps):
    inst = [median_gps_speed_in(w, gps) for w in windows]   # None se niente GPS
    for i, w in enumerate(windows):
        if w.label != "IDLE": continue
        lo, hi = max(0, i-CONTEXT), min(len(windows), i+CONTEXT+1)
        near = [s for s in inst[lo:hi] if s is not None]
        if near and max(near) >= VEHICLE_SPEED_MPS:
            w.label = "MOVING_VEHICLE"
    return windows
```

---

## 5. Mobile (Flutter)

### 5.1 Schema Drift (`features/acquisition/data/acquisition_local_database.dart`)

- `schemaVersion` 1 → 2 con migrazione.
- `AcquisitionSessions` + `remoteTripId` (int, nullable) + `tripClosedSynced`/flag di finalizzazione.
- `StateTransitions` + `isSynced` (per la riconciliazione).
- `GpsPoints` / `SensorWindows`: `isSynced` già presente.

### 5.2 SyncService (nuovo)

- Riconciliatore: scansiona SQLite per ciò che ha `isSynced=false` / `remoteTripId=null` /
  sessioni chiuse-non-finalizzate, e spinge nell'**ordine** della sezione 3.
- **Idempotente**: invia solo ciò che non è ancora salito; richiamarlo due volte non duplica.
- **Chunking** finestre (~50–100 per richiesta); marca `isSynced` per riga man mano.
- **Trigger**: (a) nudge dopo lo Stop se app aperta; (b) avvio/resume app; (c) listener "rete tornata".
- `process-har` chiamato **solo** dopo create+GPS+finestre+transizioni+close.
- Riusa il **bearer token** di auth (`Authorization: Bearer`), gzip sul payload.

### 5.3 Polling (`repositories/impl/acquisition_repository_impl.dart` o nuovo)

- Dopo `process-har`: poll `GET /trips/{id}/diary` ogni N secondi finché `PROCESSED`.
- Se l'app si chiude: ripartire il polling alla riapertura (stesso spirito del SyncService).

### 5.4 Aggancio

- `startTracking()`: dopo aver creato la sessione locale, **tenta** la creazione Trip remoto
  (non bloccante).
- `stopTracking()`: dopo `endSession`, **nudge** SyncService.
- DI in `di/` per registrare SyncService e iniettare la base URL + token.

---

## 6. Ordine di esecuzione consigliato

```
1. Backend: PostGIS/GeoDjango + Dockerfile GDAL + migration CREATE EXTENSION   (sblocca tutto)
2. Backend: modelli (client_session_id, GpsPoint→Point+unique, StateTransition,
            MobilitySegment, SignificantPlace) + migrazioni
3. Backend: API (get_or_create, close_trip, state-transitions, ignore_conflicts, diary)
4. Mobile:  Drift v2 (remoteTripId, isSynced su transitions) + SyncService + aggancio Start/Stop
5. Verifica end-to-end con worker PLACEHOLDER (diario finto) → conferma che il flusso dati gira
6. Backend: vendoring modello + requirements-worker (TF) + pipeline reale nel worker
7. Backend: segmentazione 2 passate + fusione GPS + luoghi significativi (PostGIS)
8. Mobile:  polling + recupero diario
```

Il passo 5 è il checkpoint chiave: prima far girare **tutto il giro dati** con un worker finto,
poi sostituire il cuore ML. Riduce il rischio di debug incrociato.

---

## 7. Punti da tarare / rischi

```
- Soglie: VEHICLE_SPEED_MPS, CONTEXT, dwell 5 min, raggio 50–100 m  → motivare in relazione
- GRU su viaggi < 64 finestre (~5 min): serve fallback (CNN/smoothing) sui bordi
- GDAL/GEOS nell'immagine Docker: attrito una-tantum del setup GeoDjango
- Idempotenza process-har: guard su Trip.status per non riscrivere il diario doppio
- Artefatto 23MB: Git LFS o volume, non git "nudo"
- Sync allo Stop offline: i dati restano in SQLite, ripresi alla riapertura (atteso)
```

---

## 8. Aggancio alla traccia (Proposta 2)

```
Tracce GPS + timestamp + segmenti + attività   → GpsPoint + MobilitySegment + ActivityLabel
MobilityTrace/Segment/SignificantPlace/Label    → §4.2 (mappatura 1:1)
Segmentazione spostamenti/soste                 → §4.4 passo 6 (2 passate)
Luoghi significativi con soglia motivata         → §4.4 passo 7 (≥ 5 min)
HAR walking/biking/driving/idle                  → CNN+GRU 5 classi
Casi ambigui (traffico, semaforo, cambio mezzo)  → fusione GPS (§4.4 passo 5) + passata 2
PostGIS per dati spaziali                         → GeoDjango (§4.1)
Distanza percorsa (statistica)                    → ST_Length / Distance annotate
```

---

## 9. Stato di implementazione (aggiornato 2026-06-10)

### 9.1 Fatto e verificato

**Backend** — verificato con smoke test della pipeline e con un test HTTP end-to-end
contro il server Django (register → trip idempotente → gps batch + dedup → finestre →
transizioni → close → process-har → diario `PROCESSED`).

```
✓ PostGIS/GeoDjango abilitato (settings, Dockerfile GDAL, migration CREATE EXTENSION)
✓ Modelli: Trip.client_session_id, GpsPoint.point (PointField geography) + unique(trip,timestamp),
  StateTransition, MobilitySegment, SignificantPlace  (migrazioni applicate)
✓ API: trip get_or_create, batch gps/finestre/transizioni con ignore_conflicts,
  close, process-har, diary
✓ Worker: normalizzazione reale (norm_stats.json) → classificatore placeholder →
  fusione GPS (IDLE↔MOVING_VEHICLE) → segmentazione 2 passate → luoghi → diario, idempotente
✓ Artefatti preprocessing copiati: mobility/ml/norm_stats.json, label_map.json
```

**Mobile** — `flutter analyze` pulito (nessun problema).

```
✓ DAO: unsyncedGpsPoints / markGpsPointsSynced / unsyncedSensorWindows / markSensorWindowsSynced
✓ AcquisitionSyncService: upload ordinato a chunk (trip→gps→finestre→transizioni→close→process-har),
  idempotente via client_session_id; chunk gps=200, finestre=50
✓ Aggancio a stopTracking (best-effort, fire-and-forget) + wiring DI (DB condiviso + token da AuthRepository)
```

### 9.2 Costruito ma NON testato a runtime

```
- L'app vera non e mai stata eseguita su device/simulatore.
  flutter analyze verifica i tipi, NON che allo Stop il SyncService parta davvero
  e i dati arrivino. Il contratto HTTP colpito e pero identico a quello gia provato.
  → DA FARE: prova reale su telefono (Start → muoviti → Stop → controlla i dati in /admin).
```

### 9.3 Cosa manca (TODO, in ordine di priorita)

```
1. RETRY / RICONCILIATORE OLTRE LO STOP  [priorita alta]
   Oggi il sync parte SOLO da stopTracking (_scheduleSync). Manca il ri-trigger su
   avvio/resume app e su "rete tornata". Conseguenza: se lo Stop avviene OFFLINE,
   i dati restano in SQLite (isSynced=false) e NESSUNO li ri-manda.
   → serve: all'avvio app, scansionare le sessioni con righe non sincronizzate e
     richiamare syncSession; opz. listener connettivita (richiede pacchetto connectivity_plus).
   File: acquisition_repository_impl.dart, acquisition_sync_service.dart

2. LETTURA DIARIO LATO APP  [feature successiva]
   L'app manda i dati ma non rilegge il diario: niente polling di GET /trips/{id}/diary
   finche status=PROCESSED, niente schermata diario/mappa. Nessuna UI consuma il risultato.

3. WORKER CELERY ACCESO
   process-har e async: senza worker in esecuzione i dati grezzi arrivano ma il diario
   non viene prodotto (Trip resta CLOSED, non PROCESSED). Documentare/automatizzare l'avvio.

4. MODELLO REALE (oggi placeholder)
   classifier.py usa bande di velocita GPS. Da sostituire con CNN+GRU:
   - versionare i .keras (CNN 23MB + GRU 921KB) nel backend (Git LFS / volume)
   - TensorFlow SOLO nell'immagine worker → separare l'immagine web da quella worker
     (oggi condividono ninja/Dockerfile)
   - rimpiazzare classify_windows() in classifier.py; il resto della pipeline resta uguale

5. remoteTripId PERSISTITO  [ottimizzazione]
   Oggi non si salva l'id del Trip remoto: ci si affida all'idempotenza backend
   (get_or_create su client_session_id, ri-POST a ogni sync). Funziona, ma persistere
   remoteTripId (schema Drift v2) evita la ri-creazione e velocizza i retry.

6. isSynced SULLE STATETRANSITIONS  [ottimizzazione]
   Oggi le transizioni vengono ri-mandate tutte a ogni sync (il backend deduplica via
   unique constraint). Aggiungere isSynced per mandarne solo le nuove.

7. gzip DEL PAYLOAD  [ottimizzazione]
   Il chunking c'e; manca la compressione gzip sulle richieste (utile per le finestre).

8. RIMANDATI PER SCELTA (rami separati)
   - acquisizione sensori in background (requisito futuro, lavoro a se)
   - sync in background OS (WorkManager / BGTaskScheduler)
   - chiusura automatica del viaggio da parte dell'FSM
   - luoghi ricorrenti cross-viaggio (+2pt, ST_ClusterDBSCAN)
   - privacy (vista precisa vs aggregata/perturbata, +3pt)
   - dashboard web
```

### 9.4 Come provarla adesso

```bash
# infra
cd back-end/infra && docker compose up -d db redis
# backend (con GDAL per GeoDjango)
cd ../ninja && export GDAL_LIBRARY_PATH=/opt/homebrew/lib/libgdal.dylib GEOS_LIBRARY_PATH=/opt/homebrew/lib/libgeos_c.dylib
../.venv/bin/python manage.py migrate && ../.venv/bin/python manage.py runserver
# worker (necessario per produrre il diario)
../.venv/bin/celery -A config worker -l info
# app
cd ../../mobile/diary && flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000/api
```
Allo Stop l'app crea il Trip e fa il POST dei dati grezzi. Ispezione: `/admin/` oppure
`GET /api/mobility/trips/{id}/diary`.
