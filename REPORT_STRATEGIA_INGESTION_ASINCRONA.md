# Strategia di Ingestione Asincrona per i Viaggi

> Versione 2 — rivista dopo l'analisi architetturale del 2026-06-12.
> Questa versione sostituisce la proposta iniziale e riflette le decisioni
> prese contestualizzandole sul codice reale e su un target di ~1000 utenti
> registrati. Le scelte sono motivate nella sezione "Decisioni Architetturali".
>
> STATO: la parte finale del flusso (HAR finale + cancellazione dei blob raw)
> e' CONGELATA. Oggi non esiste ancora un'interrogazione diretta del modello
> HAR. Il codice va PREDISPOSTO (interfacce, hook, punto di cancellazione) ma:
>   - HAR finale non viene invocato finche' il modello non e' integrato;
>   - i blob raw NON vengono MAI cancellati per ora (retention illimitata).
> La cancellazione event-driven si attivera' solo quando HAR sara' operativo.

## Obiettivo

Caricare dal mobile al backend i dati di un viaggio in modo:

- affidabile e ritentabile;
- non bloccante per l'utente allo stop;
- scalabile fino a ~1000 utenti registrati;
- sostenibile come volume dati a riposo;
- compatibile con HAR finale offline.

La strategia in una frase:

```text
Il mobile consegna al backend un pacchetto grezzo affidabile.
Il backend, in asincrono, lo trasforma in un viaggio definitivo.
Il mobile non "salva il viaggio nel backend" durante lo stop.
```

---

## Contesto Reale del Progetto (profilo d'uso assunto)

Le decisioni di questo documento valgono per questo profilo. Se cambia,
vanno rivalutate.

```text
Scala target:        ~1000 utenti registrati.
Profilo di carico:   volume-bound, NON concurrency-bound.
                     i viaggi si chiudono in momenti sparsi nella giornata,
                     quindi poche richieste/sec ma molti dati a riposo.
Viaggi:              possono durare ore; rete spesso mobile e inaffidabile.
Sensor window raw:   usa-e-getta. HAR le consuma una volta e poi non
                     servono piu' al prodotto.
Ripresa upload:      opportunistica (all'apertura app + rete). Il vero
                     background a app killata e' un incremento futuro.
```

Conseguenza centrale: a questa scala **il collo di bottiglia non e' quante
POST al secondo ricevi, ma quanti GB di sensor window accumuli**. Tutto il
resto del design discende da qui.

---

## Stato Implementato nel Codice

Questa sezione descrive il flusso oggi presente nel codice dopo gli step 1-7.

```text
Backend:
  - MinIO/S3 configurato tramite S3_* env var
  - storage helper con presigned PUT, HEAD, GET e delete gated
  - TripIngestion e TripIngestionPart separati da Trip
  - endpoint create / presign / confirm / complete / status
  - presigned PUT diretto a object storage: Django non riceve i blob pesanti
  - confirm verifica size via HEAD e sha256 tramite metadata S3
  - Celery process_trip_ingestion materializza Trip + GPS + transizioni
  - sensor window raw restano solo blob in object storage
  - HAR finale congelato: non invocato, cleanup raw disattivato

Mobile:
  - SyncJob persistente in SQLite
  - STOP non bloccante: chiude la sessione locale, crea SyncJob, torna idle
  - packaging gzip su disco
  - upload orchestrato con presign -> PUT -> confirm -> complete
  - retry/backoff opportunistico
  - polling dello stato backend via SyncJob
  - UI mostra lo stato sync: in coda / packaging / upload / analisi backend /
    completato / errore retryable / errore finale
```

Stato terminale attuale:

```text
PROCESSED = Trip materializzato con GPS + transizioni.
COMPLETED = futuro, quando HAR finale sara' operativo.
```

Quindi oggi un viaggio correttamente ingerito arriva a `PROCESSED`, non a
`COMPLETED`.

---

## Punto di Partenza Storico del Codice

Cosa esiste gia':

```text
Mobile (AcquisitionSyncService):
  - sync chunked (200 GPS / 50 window) eseguito DENTRO stopTracking()
  - flag isSynced per riga + retry parziale grezzo
  - NESSUNA persistenza del job, NESSUN backoff
  - JSON NON compresso
  - lo stop ATTENDE il sync: se l'app muore a meta', il sync e' perso

Backend (Django Ninja):
  - endpoint sincroni che fanno bulk_create DENTRO la richiesta HTTP
  - SensorWindow.matrix salvata come JSONField su Postgres
  - process-har enqueue Celery (gia' asincrono)

Modelli:
  - idempotenza gia' presente: Trip.client_session_id unique,
    GpsPoint(trip,timestamp) unique, SensorWindow(trip,start,end) unique,
    StateTransition(trip,timestamp,to_state) unique
  - SensorWindow ha gia' un campo object_key inutilizzato

Infra:
  - Redis + Celery gia' configurati
  - NESSUN object storage (MinIO/S3) ancora presente
```

Questa era la situazione di partenza prima degli step implementativi. Oggi il
flusso nuovo convive ancora con alcuni endpoint legacy, ma il percorso
principale di sync mobile usa `TripIngestion` + object storage.

---

## I Due Problemi Veri

A questa scala i problemi reali sono solo due, e sono indipendenti:

```text
1. VOLUME a riposo
   Le matrici 500x9 finiscono in Postgres (JSONField).
   1000 utenti x ~4 viaggi/giorno x ~360 window x 4500 float
   = ~1,44M window/giorno => decine di GB/giorno di TOAST e bloat.
   Questo distrugge il database transazionale.

2. WEB WORKER occupati
   Oggi il bulk_create delle sensor window avviene DENTRO la richiesta HTTP.
   Anche con pochi upload/sec, ogni upload tiene occupato un worker gunicorn
   per secondi. Con upload pesanti su rete lenta, e' il primo punto a rompersi.
```

La macchina di trasporto elaborata (parti, manifest, polling) **non** e' il
problema principale: l'idempotenza la danno gia' i unique constraint.

---

## Architettura Concordata

```text
MOBILE (stop non bloccante)
  STOP
    -> chiudi sessione locale, salva tutto nel DB locale
    -> crea un SyncJob persistente
    -> torna SUBITO a UI idle
  Coda SyncJob (DB locale) gestisce upload con retry/backoff,
  ripresa opportunistica all'apertura app + rete.

  Packaging locale (file su disco, compressi):
    gps_points.json.gz
    state_transitions.json.gz
    sensor_windows_part_0001.json.gz
    sensor_windows_part_0002.json.gz   (chunk 5-20 MB)
    ...

  POST /ingestion/trips               -> crea TripIngestion, ritorna ingestion_id   [worker libero]
  POST /ingestion/{id}/parts/presign  -> presigned PUT URL per (kind, sequence)      [worker libero]
  PUT  <presigned-url>                -> blob DIRETTO su object storage S3-compat.    [NESSUN worker]
  POST /ingestion/{id}/parts/confirm  -> registra Part(sha256, size) via HEAD        [worker libero]
  POST /ingestion/{id}/complete       -> verifica parti -> enqueue Celery -> 202

CELERY
  process_trip_ingestion:
    leggi blob GPS + transitions
    BEGIN tx (LEGGERA: niente matrici)
      materializza Trip + GpsPoint + StateTransition
    COMMIT
    (in futuro) enqueue HAR — PER ORA NON invocato

  process_trip_har:   [CONGELATO — predisposto ma non attivo]
    legge i blob sensor_windows da object storage
    produce label / segmenti
    scrive MobilitySegment + label su PostGIS
    on SUCCESS -> (in futuro) cancella i blob raw di quel viaggio
    PER ORA: HAR finale non invocato; i blob raw NON vengono mai cancellati.

POSTGIS  ->  SOLO dati leggeri:
             Trip, GpsPoint, StateTransition, MobilitySegment, label
             Le matrici 500x9 NON entrano MAI qui.

OBJECT STORAGE (MinIO in dev/locale, Railway Buckets in deploy — D7)
             Blob grezzi: retention ILLIMITATA per ora (MAI cancellati).
             La cancellazione event-driven dopo HAR success e' predisposta
             ma disattivata finche' HAR non e' operativo.
```

---

## Decisioni Architetturali

Le dieci scelte che definiscono questo design, con la motivazione.

### D1 — Driver: scala, non un incendio in corso
Si progetta per ~1000 utenti "fatto bene", non per spegnere un problema gia'
osservato. Quindi si privilegiano scelte che reggono la scala, evitando pero'
complessita' che la scala reale non richiede.

### D2 — Carico: volume-bound, non concurrency-bound
I viaggi si chiudono in momenti diversi: la concorrenza di richieste e'
modesta. Il problema dominante e' il volume dati a riposo. L'energia va su
storage e processing, non su un protocollo di trasporto barocco.

### D3 — Raw usa-e-getta
Dopo che HAR ha prodotto le label, i campioni grezzi 500x9 non servono piu'
al prodotto. Non vanno conservati a lungo in storage interrogabile.

### D4 — Le sensor window NON entrano in Postgres
Diretta conseguenza di D2 + D3. Le matrici vivono come blob in object storage,
consumate da HAR e poi cancellate. In Postgres, al massimo, una riga metadata
`SensorWindow(object_key, start, end, label)` SENZA il campo `matrix`.
Il `matrix` JSONField va deprecato. Il campo `object_key` gia' esistente e' il
gancio. Questo elimina il problema volume alla radice.

### D5 — Ripresa upload opportunistica (per ora)
Coda `SyncJob` persistente + retry/backoff + stop non bloccante. La ripresa
avviene all'apertura app con rete. Il background vero a app killata
(URLSession background transfer / WorkManager) e' un incremento futuro,
isolato, che non tocca la logica di coda.
Limite di prodotto da tenere d'occhio: un viaggio non si sincronizza finche'
l'utente non riapre l'app.

### D6 — `TripIngestion` separata dal `Trip`
L'upload sporco (chunk parziali, retry, fallimenti) vive su `TripIngestion`.
Il `Trip` di dominio lo crea Celery, in transazione, solo a processing
riuscito. Cosi' la tabella `Trip` contiene SOLO viaggi puliti e completi, e
non va mai filtrata per "validi vs monchi". L'idempotenza
`unique(user, client_session_id)` si sposta sull'ingestion.

### D7 — Presigned URL (upload diretto a object storage)
Il mobile NON carica i blob attraverso Django. Chiede un presigned PUT URL
(chiamata leggera) e carica il blob direttamente su object storage. Il web
worker non tocca mai i byte pesanti, quindi un client lento non occupa un
worker. `confirm` verifica sha256/size leggendo i metadata dell'oggetto (HEAD),
non i byte.

Scelta dello storage (progetto universitario, backend gia' su Railway Hobby
$5/mese):

```text
Dev / locale:        MinIO in docker-compose   (container in piu', gratis, offline)
Railway (staging/prod): Railway Buckets        (S3-compatibile nativo, $0.015/GB-mese,
                                                 egress e operazioni illimitati gratis,
                                                 nessun account/servizio extra)
```

Entrambi S3-compatibili: il codice (boto3 / django-storages, presigned PUT/GET)
e' identico, cambiano solo le 4 env var (`S3_ENDPOINT_URL`, `S3_ACCESS_KEY_ID`,
`S3_SECRET_ACCESS_KEY`, `S3_BUCKET_NAME`).

Perche' MinIO in locale e non Railway Buckets anche in dev (i Buckets sono
raggiungibili da rete pubblica, sarebbe possibile): l'iterazione e' molto piu'
rapida e offline (niente round-trip su internet per ogni upload di test), e lo
stato si pulisce con `docker compose down -v`. Il codice non cambia, quindi non
c'e' costo di "doppia implementazione".

Perche' Railway Buckets in deploy e non MinIO self-hosted su Railway: MinIO
costerebbe un volume a $0.15/GB-mese + egress $0.05/GB + un servizio in piu' da
gestire. Railway Buckets costa $0.015/GB-mese (10x meno), egress/API gratis e
illimitati, e il costo rientra nel credito Hobby gia' pagato (con la retention
illimitata di D9, ~65GB prima di superare $1 extra, cioe' migliaia di viaggi).
Cloudflare R2 resta un'alternativa equivalente se in futuro si volesse
disaccoppiare lo storage da Railway, ma non e' necessario per ora.

### D8 — Materializzazione in big-tx leggera; HAR separato
Poiche' in Postgres finiscono solo GPS + transizioni (D4), la transazione di
materializzazione e' piccola: una `transaction.atomic()` atomica e' sicura e
semplice. Il retry e' banale via `get_or_create(client_session_id)`. HAR resta
un task separato perche' e' lento e non deve tenere aperta una transazione DB.

### D9 — Cancellazione raw event-driven [CONGELATA — predisposta, non attiva]
Il design definitivo: "usa-e-getta" = gettati quando consumati, non a orologio.
I blob raw si cancelleranno alla fine di `process_trip_har` con esito SUCCESS,
evitando la race in cui una TTL a tempo fisso cancella le window prima che HAR
le legga (data-loss silenzioso sotto backlog).

STATO ATTUALE: HAR finale non e' ancora integrato (nessuna interrogazione
diretta del modello). Quindi, per ora:

```text
- i blob raw NON vengono MAI cancellati (retention illimitata)
- NESSUNA lifecycle TTL attiva sul bucket
- il punto di cancellazione e' predisposto nel codice ma disattivato
  (es. dietro un flag HAR_CLEANUP_ENABLED = False)
```

Si attivera' la cancellazione solo quando HAR sara' operativo e validato.

### D10 — Chunking giustificato dai viaggi lunghi
Con viaggi di ore su rete mobile, un POST unico da decine di MB e' fragile.
Si divide in parti da 5-20 MB compresse, con retry della sola parte fallita.
Le parti sono blob diretti su object storage (D7), non multipart attraverso
l'API.

---

## API Backend

Tutti gli endpoint richiedono `Authorization: Bearer <token>` e verificano che
l'ingestion appartenga all'utente autenticato.

### 1. Creazione Ingestion

```text
POST /api/ingestion/trips
```

Body:

```json
{
  "client_session_id": "local-session-uuid",
  "schema_version": 1,
  "started_at": "2026-06-12T10:00:00Z",
  "ended_at": "2026-06-12T10:35:00Z",
  "timezone": "Europe/Rome",
  "expected_parts": { "gps": 1, "transitions": 1, "sensor_windows": 6 }
}
```

Risposta (idempotente su `client_session_id`):

```json
{ "ingestion_id": "server-ingestion-uuid", "status": "CREATED", "already_exists": false }
```

### 2. Richiesta Presigned URL per una parte

```text
POST /api/ingestion/trips/{ingestion_id}/parts/presign
```

Body:

```json
{ "kind": "sensor_windows", "sequence": 3, "sha256": "abc123...", "size_bytes": 9437184 }
```

Risposta:

```json
{
  "object_key": "ingestions/<id>/sensor_windows_part_0003.json.gz",
  "upload_url": "https://minio.../presigned-put...",
  "upload_headers": {
    "Content-Type": "application/gzip",
    "x-amz-meta-sha256": "abc123..."
  },
  "expires_in": 900
}
```

Il backend NON riceve il file. Restituisce solo l'URL firmato e gli header che
il mobile deve mandare nel PUT.

### 3. Upload diretto (mobile -> object storage)

```text
PUT <upload_url>
Content-Type: application/gzip
x-amz-meta-sha256: abc123...
body = blob gzip
```

Nessun web worker coinvolto.

### 4. Conferma parte

```text
POST /api/ingestion/trips/{ingestion_id}/parts/confirm
```

Body:

```json
{ "kind": "sensor_windows", "sequence": 3, "sha256": "abc123..." }
```

Il backend fa HEAD sull'oggetto, verifica `size` e `sha256` nei metadata S3, e registra
`TripIngestionPart`. Risposte: `RECEIVED`, `ALREADY_RECEIVED`, oppure
`409 Conflict` se lo stesso `(kind, sequence)` arriva con sha256 diverso.

### 5. Complete

```text
POST /api/ingestion/trips/{ingestion_id}/complete
```

Verifica che tutte le parti dichiarate in `expected_parts` siano confermate,
porta l'ingestion a `QUEUED`, enqueue Celery, risponde `202 Accepted`.
Da qui in poi il mobile non aspetta il processing.

Nota:

```text
READY_TO_PROCESS esiste come stato di modello, ma nel flusso attuale il codice
passa direttamente a QUEUED dopo la verifica delle parti.
```

### 6. Stato

```text
GET /api/ingestion/trips/{ingestion_id}
```

```json
{
  "ingestion_id": "server-ingestion-uuid",
  "status": "PROCESSING",
  "received_parts": ["gps_points.json.gz", "sensor_windows_part_0001.json.gz"],
  "missing_parts": ["sensor_windows_part_0002.json.gz"],
  "trip_id": null,
  "error": null
}
```

Il mobile usa `missing_parts` per ritentare solo cio' che manca.

---

## Modello Dati Backend

### TripIngestion (aggregato di upload)

```text
TripIngestion
  id
  user_id
  client_session_id        UNIQUE con user_id
  schema_version
  status
  expected_parts           (json: per kind, quante parti)
  raw_base_path            (prefix object storage)
  manifest_sha256
  total_size_bytes
  created_at / updated_at
  queued_at / started_processing_at / completed_at / failed_at
  error_message
  trip_id                  (FK al Trip materializzato, null finche' non processato)

Vincolo: unique(user_id, client_session_id)
```

### TripIngestionPart

```text
TripIngestionPart
  id
  ingestion_id
  kind                     (gps_points | state_transitions | sensor_windows)
  sequence
  sha256
  size_bytes
  object_key
  received_at

Vincoli: unique(ingestion_id, kind, sequence)
```

### Stati Ingestion

```text
CREATED            ingestion creata, nessuna parte confermata
RECEIVING          alcune parti confermate
READY_TO_PROCESS   tutte le parti presenti e verificate
QUEUED             job Celery in coda
PROCESSING         Celery sta materializzando
PROCESSED          Trip materializzato (GPS + transizioni). Stato finale PER ORA,
                   in attesa di HAR.
COMPLETED          (futuro) Trip + HAR completato. Solo quando HAR sara' attivo.
FAILED_RETRYABLE   errore temporaneo
FAILED_FINAL       errore definitivo (file corrotto, schema invalido)
```

### Dominio (PostGIS) — invariato e leggero

```text
Trip, GpsPoint(geography), StateTransition, MobilitySegment, SignificantPlace, HarJob
SensorWindow  -> SOLO metadata + object_key + label, MAI la matrice grezza
```

---

## Mobile: SyncJob Locale

Tabella nel DB locale (Drift) per disaccoppiare lo stato viaggio dallo stato
sync.

```text
SyncJob
  id
  local_session_id
  remote_ingestion_id
  status            (PENDING | PACKAGING | UPLOADING | WAITING_PROCESSING |
                     COMPLETED | FAILED_RETRYABLE | FAILED_FINAL)
  attempts
  next_retry_at
  last_error
  created_at / updated_at
```

Backoff consigliato:

```text
tentativo 1: subito
tentativo 2: dopo 10 s
tentativo 3: dopo 30 s
tentativo 4: dopo 2 min
tentativo 5: dopo 10 min
```

Comportamento allo STOP:

```text
STOP
  -> chiudo il viaggio locale e salvo tutto
  -> creo SyncJob (PENDING)
  -> torno SUBITO a UI idle      (NON attendo la rete)
La coda processa il SyncJob in modo opportunistico, e riprende
all'apertura app se interrotta.
```

UX: distinguere sempre stato viaggio (concluso localmente) da stato sync
(in attesa / caricamento / processamento / completato).

### UI sync state implementata

La home mobile mostra lo stato dell'ultimo `SyncJob` noto:

```text
PENDING              -> Sync in coda
PACKAGING            -> Preparazione pacchetto
UPLOADING            -> Upload viaggio
WAITING_PROCESSING   -> Analisi backend
COMPLETED            -> Viaggio sincronizzato
FAILED_RETRYABLE     -> Sync in attesa / riprova
FAILED_FINAL         -> Sync fallita
```

Il pulsante Stop non dichiara piu' "sincronizzato con successo": dice che il
viaggio e' salvato localmente e che la sincronizzazione prosegue in background.

Quando il backend e' in `QUEUED`, `PROCESSING` o `FAILED_RETRYABLE`, il mobile
non ricarica i blob e non richiama `complete`: resta in polling con
`WAITING_PROCESSING`. Se il backend arriva a `FAILED_FINAL`, il job locale
diventa `FAILED_FINAL`.

---

## Formati

```text
gps_points.json.gz          punti GPS (UTC, WGS84, speed m/s, accuracy m, null se assente)
state_transitions.json.gz   timeline decisionale FSM (from/to/reason/timestamp/metadata)
sensor_windows_part_*.json.gz   window 500x9, chunk 5-20 MB compressi
```

Per ora JSON gzip: semplice da debuggare, e i raw sono comunque usa-e-getta e
interni a HAR. In futuro, se serve ridurre banda mobile, si valuta un formato
binario compatto (float32 colonnare / MessagePack / Parquet) senza cambiare il
resto dell'architettura.

---

## Cosa Fa Celery

```text
process_trip_ingestion(ingestion_id):
  1. carica TripIngestion, verifica parti presenti e checksum
  2. status -> PROCESSING
  3. legge blob gps + transitions
  4. BEGIN transaction.atomic():
       get_or_create(Trip by client_session_id)
       bulk_create(GpsPoint, ignore_conflicts)
       bulk_create(StateTransition, ignore_conflicts)
     COMMIT
  5. (in futuro) enqueue process_trip_har — PER ORA NON invocato.
     L'ingestion arriva fino a Trip materializzato; HAR resta in sospeso.

process_trip_har(trip_id, ingestion_id):   [CONGELATO — predisposto, non attivo]
  1. legge i blob sensor_windows da object storage
  2. esegue HAR finale -> label / MobilitySegment
  3. scrive su PostGIS
  4. on SUCCESS:
       (in futuro) cancella i blob raw dell'ingestion
       ingestion.status -> COMPLETED
  5. on FAILURE:
       salva error, status -> FAILED_RETRYABLE / FAILED_FINAL
       NON cancella i blob (servono al retry)

PER ORA: il task e' predisposto come stub/interfaccia ma non viene invocato,
e in nessun caso cancella i blob raw.
```

Le matrici grezze restano in object storage a tempo indeterminato finche' HAR
non sara' operativo. A quel punto si attivera' la cancellazione post-HAR (D9).

---

## Relazione con FSM e HAR

La FSM mobile resta l'autorita' sui confini operativi del viaggio (quando
parte, quando finisce, quali transizioni, quali dati raccogliere). Produce una
timeline decisionale che il backend riceve come dato.

```text
FSM decide i confini operativi del viaggio.
HAR corregge e arricchisce la semantica interna del viaggio.
```

HAR lavora su dati completi e coerenti, dopo l'ingestione. Strategia HAR:

```text
CNN live:           provvisoria lato mobile
Smoothing temporale: stabilizzazione locale sugli ultimi 30-60 s
GRU/HAR finale:      correzione offline a fine viaggio (questo flusso)
```

---

## Sicurezza

```text
- ogni endpoint richiede Bearer token valido
- una parte non puo' essere associata a ingestion di un altro utente
- presigned URL a scadenza breve (es. 15 min)
- limite dimensione per parte (es. 20 MB)
- verifica sha256/size in confirm
- max active ingestions per utente configurabile
```

---

## Fasatura Consigliata

### Fase 1 — Mobile robustness (il buco vero, indipendente dal resto)

```text
- tabella SyncJob persistente
- retry con backoff
- stop NON bloccante
- gzip lato mobile
Fattibile mantenendo gli endpoint attuali.
```

### Fase 2 — Object storage + presigned

```text
- MinIO in docker-compose
- endpoint presign / confirm
- le sensor window smettono di entrare in Postgres
```

### Fase 3 — TripIngestion + materializzazione Celery

```text
- modelli TripIngestion / TripIngestionPart
- process_trip_ingestion (big-tx leggera)
- il Trip nasce qui
```

### Fase 4 — HAR su blob + cleanup event-driven [CONGELATA]

```text
PREDISPORRE ora (interfacce/stub), ATTIVARE in futuro:
- process_trip_har legge i blob da object storage
- cancellazione raw dopo HAR success      <-- DISATTIVATA finche' HAR non e' integrato
Finche' HAR non e' operativo:
- HAR finale non viene invocato
- i blob raw NON vengono mai cancellati (retention illimitata)
```

### Fase 5 — Background upload vero (solo se diventa requisito)

```text
- URLSession background transfer (iOS) / WorkManager (Android)
- isolato: non tocca la logica di coda SyncJob
```

---

## Decisione Consigliata per il Progetto

```text
Viaggio unico a livello logico.
Upload a parti compresse, DIRETTE su object storage via presigned URL.
Backend registra solo metadata, mai i byte pesanti.
Celery materializza Trip+GPS+transizioni in big-tx leggera.
HAR (FUTURO, predisposto): leggera' i blob raw e produrra' le label;
  solo allora i raw verranno cancellati. PER ORA i raw restano per sempre.
PostGIS conserva solo dati strutturati leggeri.
```

La frase chiave resta:

```text
Il mobile non deve "salvare il viaggio nel backend" durante lo stop.
Il mobile consegna un pacchetto grezzo affidabile.
Il backend, in asincrono, lo trasforma in viaggio definitivo.
```

E il principio che a 1000 utenti conta piu' di tutti:

```text
Le matrici grezze non entrano mai nel database transazionale,
e non passano mai dai web worker.
```
