# Strategia di Ingestione Asincrona per i Viaggi

> Versione 3 — aggiornata al 2026-07-07 dopo l'introduzione del flusso raw
> binario, della pipeline HAR finale attiva e della migrazione mobile
> `matrixJson -> matrixBlob`.
>
> Nota di lettura: le sezioni storiche piu' sotto restano utili per capire le
> decisioni architetturali. In caso di conflitto, prevale la sezione
> "Stato Attuale — Versione 3" di questo documento.
>
> AGGIORNAMENTO 2026-06-21: il Core Ingestion piccolo (GPS points e state
> transitions) usa come percorso primario `POST /api/ingestion/trips/core`.
> Il flusso presigned/object-storage resta il percorso primario per i raw
> pesanti e resta compatibile per il core legacy dei client vecchi.
>
> AGGIORNAMENTO 2026-07-07: i raw sensor windows non sono piu' JSON gzip.
> Il mobile salva localmente `matrix_blob` float32 e carica parti
> `sensor_windows_part_XXXX.bin.gz`. Il backend decodifica il formato binario,
> accoda `process_trip_har_final`, esegue CNN+GRU nel worker Celery, scrive i
> segmenti del diario e poi accoda il mining dei luoghi significativi.

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

## Stato Attuale — Versione 3

Questa e' la fotografia operativa del sistema dopo gli ultimi interventi su
upload asincrono, formato binario e pipeline HAR.

### Flusso End-to-End Attuale

```text
MOBILE
  Tracking in corso
    -> SQLite locale:
       - GPS points
       - State transitions FSM
       - Sensor windows HAR come matrix_blob float32 500x6

  Stop
    -> chiude la sessione locale
    -> crea/aggiorna SyncJob persistente
    -> torna subito alla UI idle

  TripSyncQueue
    -> costruisce Core inline JSON deterministico
    -> POST /api/ingestion/trips/core
    -> riceve ingestion_id/trip_id quando il Core e' materializzato
    -> costruisce raw parts binarie:
       sensor_windows_part_0001.bin.gz
       sensor_windows_part_0002.bin.gz
       ...
    -> per ogni raw part:
       presign -> PUT diretto su object storage -> confirm
       con upload parallelo limitato
    -> complete-raw
    -> polling rapido mentre il backend e' QUEUED/PROCESSING

BACKEND WEB
  /trips/core
    -> valida hash del Core
    -> crea/recupera TripIngestion
    -> materializza Trip + GpsPoint + StateTransition + LineString
    -> core_status=COMPLETED

  /parts/presign
    -> genera object_key deterministico
    -> firma PUT S3-compatible

  /parts/confirm
    -> verifica l'oggetto con HEAD
    -> controlla size e metadata sha256
    -> marca la parte come ricevuta

  /complete-raw
    -> verifica che tutte le raw parts siano confermate
    -> raw_status=QUEUED
    -> crea HarJob FINAL_TRIP
    -> accoda process_trip_har_final(job_id, ingestion_id)

CELERY WORKER
  process_trip_har_final
    -> claim idempotente dell'ingestion raw
    -> legge raw parts da object storage
    -> gunzip
    -> decodifica binaria MDHARW1
    -> passa finestre 500x6 float32 alla pipeline
    -> CNN extractor + GRU batchata
    -> correzione IDLE con velocita GPS
    -> segmentazione e virtual stops
    -> scrive MobilitySegment / VirtualStopInterval
    -> Trip.status=PROCESSED
    -> raw_status=COMPLETED
    -> accoda mining luoghi significativi user-scoped
```

### Formato Raw Sensor Windows

Il formato raw corrente e':

```text
file fisico: sensor_windows_part_XXXX.bin.gz
content-type upload: application/gzip
payload decompresso: binario little-endian
magic: MDHARW1\0
```

Struttura del payload decompresso:

```text
header globale:
  magic[8]        = "MDHARW1\0"
  window_count u32

per ogni finestra:
  start_timestamp_us i64   # epoch microseconds UTC
  end_timestamp_us   i64
  frequency_hz       u32
  sample_count       u32   # atteso: 500 in produzione
  channel_count      u32   # atteso: 6
  samples            float32[sample_count * 6]
```

I 6 canali sono:

```text
accelerometro: x, y, z
giroscopio:    x, y, z
```

Il magnetometro non viene piu' raccolto, salvato o inviato nel percorso HAR.
Il backend accetta ancora payload JSON legacy e, se arrivano righe a 9 canali,
usa solo i primi 6 per compatibilita'.

### Formato Locale Mobile

La tabella Drift `sensor_windows` non usa piu' `matrix_json` nel modello
applicativo. Lo schema corrente usa:

```text
matrix_blob BLOB NOT NULL
```

Il blob e' lo stesso layout numerico usato nel payload raw, senza header:

```text
float32 little-endian, righe consecutive, 6 canali per sample
byte per finestra standard = 500 * 6 * 4 = 12.000 byte
```

La migration mobile `schemaVersion=7` aggiunge `matrix_blob` e converte le
righe legacy da `matrix_json`. La colonna fisica vecchia puo' restare nei DB
aggiornati, ma non e' piu' usata dal codice applicativo.

### Stati Attuali

```text
core_status=PENDING/RECEIVING/RECEIVED
  stato di ricezione del Core nel path legacy a parti.

core_status=COMPLETED
  Trip materializzato con GPS, transizioni e path.

raw_status=PENDING/RECEIVING/RECEIVED
  raw parts attese o ricevute ma non ancora accodate al worker finale.

raw_status=QUEUED/PROCESSING
  HAR finale accodato o in esecuzione su Celery.

raw_status=COMPLETED
  HAR finale completato, segmenti scritti e diary arricchito.

raw_status=FAILED_RETRYABLE
  errore temporaneo: il worker o il mobile possono ritentare.

raw_status=FAILED_FINAL
  payload raw invalido o errore non recuperabile.
```

Per la UI mobile:

```text
core_status=COMPLETED  -> il Viaggio e' visibile.
raw_status=COMPLETED   -> il Viaggio e' completato/arricchito.
```

Il polling mobile e' piu' aggressivo subito dopo una complete o quando il
backend e' `QUEUED/PROCESSING` (2 secondi), poi torna al delay normale per stati
retryable.

### Ottimizzazioni Gia' Presenti

```text
1. Raw binario float32 invece di JSON:
   elimina parsing JSON pesante e riduce dimensione/CPU.

2. `matrix_blob` locale:
   evita di salvare/parlare JSON nel DB mobile.

3. Upload raw parallelo limitato:
   piu' parti possono fare presign/PUT/confirm contemporaneamente.

4. Decoder backend NumPy:
   il binario viene letto come float32 senza passare da liste Python inutili.

5. GRU batchata:
   il worker fa una sola predict su batch di sequenze invece di una predict per
   ogni blocco da 32 finestre.

6. Timing HAR:
   i log `HAR_TIMING` separano read S3, gzip, decode binario, classify,
   segmentazione e totale.
```

Esempio di log atteso:

```text
HAR_TIMING ingestion_id=... raw_parts=... windows=...
  raw_s3_read_ms=...
  raw_gzip_ms=...
  raw_binary_decode_ms=...
  pipeline_classify_ms=...
  pipeline_total_ms=...
  total_ms=...
```

### Cleanup Raw

Il cleanup dei blob raw resta gated da `HAR_CLEANUP_ENABLED`. Il sistema ora e'
in grado di completare HAR finale, ma la cancellazione automatica va attivata
solo quando si decide esplicitamente la policy di retention. Finche' il flag e'
false, i blob restano nello storage anche dopo `raw_status=COMPLETED`.

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

Questa sezione descrive il flusso oggi presente nel codice dopo il passaggio a
raw binario e HAR finale attivo.

```text
Backend:
  - MinIO/S3 configurato tramite S3_* env var
  - storage helper con presigned PUT, HEAD, GET e delete gated
  - TripIngestion e TripIngestionPart separati da Trip
  - una sola TripIngestion con due stati: core_status e raw_status
  - core_ingestion_mode distingue INLINE da LEGACY_PARTS
  - endpoint inline POST /api/ingestion/trips/core per GPS + transizioni piccoli
  - endpoint legacy create / presign / confirm / complete-core ancora disponibili
  - endpoint raw presign / confirm / complete-raw / status invariati
  - presigned PUT diretto a object storage per i raw: Django non riceve blob pesanti
  - confirm verifica size via HEAD e sha256 tramite metadata S3
  - inline core materializza Trip + GPS + transizioni + path nella request
  - complete-core accoda Celery solo per il core legacy a parti
  - complete-raw verifica i raw, crea HarJob FINAL_TRIP e accoda HAR finale
  - sensor window raw restano blob in object storage e vengono letti da Celery
  - decoder raw binario MDHARW1 + fallback JSON legacy
  - HAR finale attivo: CNN+GRU, correzione GPS, segmentazione, status PROCESSED
  - cleanup raw ancora disattivato dietro HAR_CLEANUP_ENABLED

Mobile:
  - SyncJob persistente in SQLite
  - stesso SyncJob, ma con core_status e raw_status locali separati
  - STOP non bloccante: chiude la sessione locale, crea SyncJob, torna idle
  - packaging core inline JSON deterministico + hash SHA-256
  - niente gzip GPS/state nel percorso nuovo
  - sensor windows salvate localmente come matrix_blob float32 500x6
  - packaging gzip su disco solo per sensor_windows raw binarie
  - raw parts: sensor_windows_part_XXXX.bin.gz
  - POST core inline prima, poi upload Raw e complete-raw se esistono raw
  - upload raw parallelo limitato
  - retry/backoff opportunistico
  - polling rapido per stati backend QUEUED/PROCESSING
  - UI principale segue il Core; il Raw e' dettaglio secondario
```

Stato terminale attuale:

```text
core_status=COMPLETED = Trip materializzato con GPS + transizioni.
raw_status=QUEUED     = raw ricevuto e HAR finale accodato.
raw_status=PROCESSING = worker Celery sta elaborando HAR finale.
raw_status=COMPLETED  = HAR finale completato oppure nessun raw era atteso.
```

Quindi oggi un viaggio correttamente ingerito e' visibile nel diario quando il
Core arriva a `COMPLETED`. Il Raw puo' completarsi dopo: questo non impedisce
la creazione del `Viaggio`, ma arricchisce il diario con segmenti HAR e luoghi.

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
flusso nuovo convive ancora con endpoint legacy, ma il percorso principale del
mobile separa meglio i mondi: Core piccolo inline su Django/PostGIS, Raw pesante
su `TripIngestion` + object storage.

---

## I Due Problemi Veri

A questa scala i problemi reali sono solo due, e sono indipendenti:

```text
1. VOLUME a riposo
   Nel vecchio flusso le matrici 500x9 finivano in Postgres (JSONField).
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

  Packaging locale nuovo:
    core inline JSON deterministico:
      gps_points: [...]
      state_transitions: [...]
      core_payload_sha256: "<hash stabile del JSON core>"
    sensor_windows_part_0001.bin.gz
    sensor_windows_part_0002.bin.gz   (chunk binari gzip)
    ...

  POST /api/ingestion/trips/core
    -> crea/recupera TripIngestion tramite client_session_id
    -> valida core_payload_sha256 e limite 1 MB
    -> materializza Trip + GPS + transizioni + LineString in transaction
    -> core_status=COMPLETED, ritorna ingestion_id/trip_id/map_available
       expected_core_parts={} e expected_raw_parts restano separati

  LEGACY: POST /api/ingestion/trips
    -> crea TripIngestion LEGACY_PARTS per client vecchi               [worker libero]
       expected_core_parts e expected_raw_parts restano separati
  POST /api/ingestion/trips/{id}/parts/presign
    -> presigned PUT URL per raw, o per core solo nel path legacy      [worker libero]
  PUT  <presigned-url>
    -> blob DIRETTO su object storage S3-compat.                      [NESSUN worker]
  POST /api/ingestion/trips/{id}/parts/confirm
    -> registra Part(sha256, size) via HEAD                           [worker libero]
  LEGACY: POST /api/ingestion/trips/{id}/complete-core
    -> verifica parti Core legacy -> enqueue Celery -> 202
       da qui il Trip legacy puo' essere materializzato
  POST /api/ingestion/trips/{id}/complete-raw
    -> verifica parti Raw -> raw_status=QUEUED -> enqueue HAR finale -> 202

CELERY
  process_trip_ingestion: [SOLO CORE LEGACY A PARTI]
    leggi blob GPS + transitions
    BEGIN tx (LEGGERA: niente matrici)
      materializza Trip + GpsPoint + StateTransition
    COMMIT
    il Core legacy materializzato puo' poi ricevere la fase Raw separata

  process_trip_har_final:
    legge i blob sensor_windows da object storage
    produce label / segmenti
    scrive MobilitySegment + label su PostGIS
    on SUCCESS -> raw_status=COMPLETED, Trip.status=PROCESSED
    cleanup raw opzionale dietro HAR_CLEANUP_ENABLED

POSTGIS  ->  SOLO dati leggeri:
             Trip, GpsPoint, StateTransition, MobilitySegment, label
             Le matrici 500x6 NON entrano MAI qui.

OBJECT STORAGE (MinIO in dev/locale, Railway Buckets in deploy — D7)
             Blob grezzi binari: retention controllata da policy/flag.
             La cancellazione event-driven dopo HAR success e' predisposta
             ma resta disattivata finche' HAR_CLEANUP_ENABLED=false.
```

### Lettura Operativa Del Diagramma

Il diagramma sopra va letto come una separazione netta tra tre piani:

```text
1. piano UX/mobile
   decide quando il viaggio e' concluso per l'utente;

2. piano upload/trasporto
   consegna in modo affidabile byte grezzi e metadata;

3. piano dominio/backend
   trasforma un upload completo in dati di prodotto.
```

La chiusura del viaggio appartiene al piano UX/mobile: quando l'utente preme
Stop, il viaggio locale e' finito. Il successo dell'upload appartiene invece al
piano di trasporto: puo' arrivare secondi o minuti dopo, senza riaprire il
tracking e senza bloccare la UI. La materializzazione del `Trip` appartiene al
piano dominio/backend: avviene solo quando il backend ha prove sufficienti che
l'upload dichiarato e' completo e consistente.

Questa distinzione evita tre errori frequenti:

```text
- non confondere "viaggio concluso" con "viaggio sincronizzato";
- non creare Trip parziali mentre l'upload e' ancora sporco;
- non far passare byte pesanti dai web worker solo per comodita' di codice.
```

---

## Invarianti Operative

Queste regole devono restare vere anche quando cambiano UI, formato dei file o
provider S3. Sono la parte piu' importante del contratto di sistema.

```text
I1. La sessione locale e' la sorgente primaria finche' il SyncJob non termina.
    I dati raccolti durante il viaggio non dipendono dalla rete.

I2. Esiste al massimo un SyncJob per local_session_id.
    Un doppio Stop o un retry non devono duplicare il lavoro locale.

I3. Esiste al massimo una TripIngestion per (user_id, client_session_id).
    Il backend deve trattare la sessione mobile come chiave di idempotenza.

I4. Esiste al massimo una parte per (ingestion_id, kind, sequence).
    Se la parte e' gia' confermata, un checksum diverso e' conflitto.

I5. Il checksum e la dimensione sono calcolati sui byte compressi finali.
    Non sul JSON non compresso e non su una rappresentazione intermedia.

I6. object_key e' deterministico rispetto a ingestion.raw_base_path, kind e
    sequence. Un retry deve puntare allo stesso oggetto logico.

I7. Il backend web non riceve mai i byte pesanti delle parti.
    Riceve solo metadata, genera URL firmati e verifica via HEAD.

I8. Postgres non contiene matrici HAR grezze nel nuovo flusso.
    I raw vivono in object storage e vengono consumati dal worker HAR.

I9. Celery puo' essere ritentato senza duplicare GpsPoint o StateTransition.
    I vincoli unique e ignore_conflicts sono parte del design, non un dettaglio.

I10. Tutti i timestamp del contratto di sync sono UTC ISO-8601.
     La timezone utente e' metadata, non va usata per ordinare eventi.

I11. `core_status=COMPLETED` significa "Trip materializzato".
     Non significa che il Raw sia stato caricato o che HAR finale sia concluso.

I12. I blob raw non si cancellano a tempo fisso.
     Se si cancellano, il punto corretto e' dopo HAR success, dietro flag/policy
     esplicita.

I13. `TripIngestion` resta unica: non esiste una ingestion Core e una ingestion
     Raw separate. La separazione e' negli stati e negli expected parts.

I14. Il Core richiede almeno una prova tra `gps_points` e `state_transitions`.
     Se manca ogni parte Core, il backend non deve creare un `Viaggio`.

I15. `complete-raw` non deve anticipare `complete-core`: il Raw arricchisce o
     prepara l'HAR, ma non sostituisce la materializzazione del viaggio.
```

### Non Obiettivi Della Versione Corrente

Alcune cose sembrano naturali ma sono volutamente fuori dallo scope corrente:

```text
- upload garantito con app killata dal sistema operativo;
- upload in background OS con URLSession/WorkManager;
- streaming live dei dati verso il backend;
- multi-device merge di viaggi dello stesso utente.
- upload garantito mentre l'app resta killata per lungo tempo;
- cancellazione automatica dei raw senza una policy di retention esplicita.
```

Il punto non e' che queste cose siano sbagliate. Il punto e' che il nucleo
attuale deve prima rendere robusto il passaggio: "sessione locale conclusa" ->
"pacchetto grezzo completo" -> "Trip materializzato".

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
Dopo che HAR ha prodotto le label, i campioni grezzi 500x6 non servono piu'
al prodotto corrente. Non devono entrare nel database transazionale; la loro
retention nello storage e' una policy operativa separata.

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

### D9 — Cancellazione raw event-driven
Il design definitivo resta: "usa-e-getta" = gettati quando consumati, non a
orologio. I blob raw si possono cancellare alla fine di `process_trip_har_final`
con esito SUCCESS, evitando la race in cui una TTL a tempo fisso cancella le
window prima che HAR le legga (data-loss silenzioso sotto backlog).

STATO ATTUALE: HAR finale e' attivo, ma la cancellazione e' ancora una policy
esplicita disattivata di default:

```text
- NESSUNA lifecycle TTL attiva sul bucket
- il punto di cancellazione resta dietro HAR_CLEANUP_ENABLED=False
- raw_status=COMPLETED non implica cancellazione fisica dei blob
```

Si attivera' la cancellazione solo quando la policy di retention sara' decisa.

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
  "device_id": "local_device",
  "app_version": "",
  "device_platform": "",
  "expected_core_parts": {
    "gps_points": 1,
    "state_transitions": 1
  },
  "expected_raw_parts": {
    "sensor_windows": 6
  }
}
```

Risposta (idempotente su `client_session_id`):

```json
{
  "ingestion_id": 123,
  "core_status": "PENDING",
  "raw_status": "PENDING",
  "already_exists": false
}
```

Dettagli importanti:

```text
- `client_session_id` e' l'UUID della sessione SQLite mobile;
- `expected_core_parts` accetta solo `gps_points` e `state_transitions`;
- `expected_raw_parts` accetta solo `sensor_windows`;
- se `expected_raw_parts` e' vuoto, il backend inizializza `raw_status=COMPLETED`;
- se l'ingestion esiste gia', il backend ritorna lo stesso `ingestion_id`;
- il client non deve assumere che `already_exists=false` al primo tentativo
  osservato: una richiesta puo' essere arrivata al backend e la risposta puo'
  essersi persa in rete;
- `started_at` e `ended_at` sono metadata dichiarati dal client e devono essere
  UTC; la timezone serve solo per ricostruzioni prodotto o debug.
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
  "object_key": "ingestions/<id>/sensor_windows_part_0003.bin.gz",
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

La richiesta e' leggera e puo' essere ripetuta. Se la parte non e' ancora
confermata, il backend puo' aggiornare sha256, size e object_key dichiarati per
gestire un re-packaging locale. Se invece `received_at` e' gia' valorizzato,
il backend deve proteggere la parte: stesso checksum = idempotente, checksum
diverso = conflitto.

Guardrail attuale:

```text
- il kind deve essere noto;
- la parte deve essere stata dichiarata negli expected parts della sua fase;
- una parte Core non puo' essere caricata quando core_status e' gia' QUEUED,
  PROCESSING, COMPLETED o FAILED_*;
- una parte Raw non puo' essere caricata quando raw_status e' COMPLETED o
  FAILED_*.
```

### 3. Upload diretto (mobile -> object storage)

```text
PUT <upload_url>
Content-Type: application/gzip
x-amz-meta-sha256: abc123...
body = blob gzip
```

Nessun web worker coinvolto.

Il presigned URL e' legato a metodo, bucket, object key, content type e metadata
firmati. Il mobile deve quindi inviare esattamente gli header ricevuti da
`presign`. In locale questo implica che `S3_PUBLIC_ENDPOINT_URL` deve essere
raggiungibile dal telefono o simulatore; l'endpoint interno Docker
(`http://minio:9000`) non basta se il client gira fuori dalla rete Docker.

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

`confirm` non deve fidarsi del fatto che il mobile dica "ho caricato". La prova
e' la HEAD sullo storage. Questo protegge da:

```text
- PUT fallito dopo presign;
- PUT parziale o tagliato dalla rete;
- upload riuscito ma verso un object_key diverso;
- metadata sha256 mancanti o non coerenti;
- retry mobile che tenta di confermare una parte vecchia.
```

### 5. Complete Core

```text
POST /api/ingestion/trips/{ingestion_id}/complete-core
```

Verifica che tutte le parti dichiarate in `expected_core_parts` siano
confermate, porta `core_status=QUEUED`, accoda Celery e risponde
`202 Accepted`. Da qui in poi il mobile non aspetta in foreground il
processing: salva `WAITING_PROCESSING` e riprende tramite polling/backoff.

`complete-core` e' il confine tra "Core ancora caricabile" e "Core pronto per
diventare Viaggio". Dopo `QUEUED`, il client non deve piu' caricare
`gps_points` o `state_transitions` su quella ingestion. Se il client riceve un
timeout dopo aver chiamato `complete-core`, deve fare `GET status`: se trova
`core_status=QUEUED`, `PROCESSING` o `COMPLETED`, la complete Core e' gia'
stata accettata.

Il backend rifiuta `complete-core` quando:

```text
- non esiste nessuna parte Core attesa;
- manca una parte Core dichiarata;
- core_status e' FAILED_FINAL.
```

### 6. Complete Raw

```text
POST /api/ingestion/trips/{ingestion_id}/complete-raw
```

Verifica che tutte le parti dichiarate in `expected_raw_parts` siano confermate.
Nel codice attuale, se tutto e' presente, imposta `raw_status=QUEUED`, crea un
`HarJob` finale e accoda `process_trip_har_final`. La cancellazione fisica dei
blob resta separata e dipende da `HAR_CLEANUP_ENABLED`.

`complete-raw` ha una precondizione forte: `core_status` deve essere
`COMPLETED`. Il Raw arricchisce il viaggio e prepara HAR; non puo' sostituire
il Core e non deve anticipare la creazione del `Viaggio`.

Nota:

```text
Raw RECEIVED non significa "HAR finito": significa solo "evidenza raw arrivata
in object storage". Dopo `complete-raw`, la fase Raw usa `QUEUED`,
`PROCESSING` e `COMPLETED` per il job HAR finale.
```

### 7. Stato

```text
GET /api/ingestion/trips/{ingestion_id}
```

```json
{
  "ingestion_id": 123,
  "core_status": "PROCESSING",
  "raw_status": "RECEIVING",
  "received_core_parts": [
    { "kind": "gps_points", "sequence": 1 }
  ],
  "missing_core_parts": [
    { "kind": "state_transitions", "sequence": 1 }
  ],
  "received_raw_parts": [
    { "kind": "sensor_windows", "sequence": 1 }
  ],
  "missing_raw_parts": [
    { "kind": "sensor_windows", "sequence": 2 }
  ],
  "trip_id": null,
  "error": null,
  "core_progress": 50,
  "raw_progress": 17
}
```

Il mobile usa `missing_core_parts` per ritentare solo il Core mancante, poi
`missing_raw_parts` per caricare i raw dopo che il Core e' completato.

### Semantica Idempotente Degli Endpoint

```text
POST /api/ingestion/trips
  Chiave: (user_id, client_session_id).
  Retry atteso: ritorna la stessa TripIngestion.
  Errore finale: payload semanticamente incompatibile con ingestion esistente
  (oggi non ancora validato in modo forte).

POST /api/ingestion/trips/{ingestion_id}/parts/presign
  Chiave: (ingestion_id, kind, sequence).
  Retry atteso: ritorna un URL valido per lo stesso object_key logico.
  Conflitto: parte non dichiarata, fase non ricevente, oppure parte gia'
  confermata con checksum diverso.

PUT <presigned-url>
  Chiave: object_key.
  Retry atteso: sovrascrive lo stesso oggetto prima della conferma.
  Dopo conferma: il client non dovrebbe piu' sovrascrivere.

POST /api/ingestion/trips/{ingestion_id}/parts/confirm
  Chiave: (ingestion_id, kind, sequence, sha256).
  Retry atteso: `ALREADY_RECEIVED` se gia' confermata.
  Conflitto: sha dichiarato diverso o HEAD non coerente.

POST /api/ingestion/trips/{ingestion_id}/complete-core
  Chiave: ingestion_id.
  Retry atteso: ritorna 202 se il Core e' gia' QUEUED, PROCESSING, COMPLETED
  o FAILED_RETRYABLE.
  Conflitto: parti Core mancanti, nessuna parte Core attesa, o FAILED_FINAL.

POST /api/ingestion/trips/{ingestion_id}/complete-raw
  Chiave: ingestion_id.
  Retry atteso: ritorna 202 se il Raw e' gia' RECEIVED o COMPLETED.
  Conflitto: Core non ancora COMPLETED, parti Raw mancanti, o FAILED_FINAL.

GET /api/ingestion/trips/{ingestion_id}
  Sempre safe: e' il modo canonico per riprendere dopo crash, timeout o app kill.
```

Il principio e': il client puo' perdere qualsiasi risposta HTTP e deve poter
ricostruire lo stato con `GET status` senza duplicare dati di dominio.

---

## Modello Dati Backend

### TripIngestion (aggregato di upload)

```text
TripIngestion
  id
  user_id
  client_session_id        UNIQUE con user_id
  schema_version
  core_status              (PENDING/RECEIVING/RECEIVED/QUEUED/PROCESSING/...)
  raw_status               (stesso vocabolario, semantica di fase diversa)
  expected_core_parts      (json: gps_points/state_transitions -> count)
  expected_raw_parts       (json: sensor_windows -> count)
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

`TripIngestion` non ha piu' uno stato aggregato unico. Ha due stati separati:

```text
core_status  descrive la fase minima che crea il Viaggio.
raw_status   descrive la fase sensori/raw, incluso HAR finale.
```

Il vocabolario e' intenzionalmente uguale per entrambe le fasi:

```text
PENDING            fase dichiarata ma nessuna parte ancora in upload
RECEIVING          almeno una parte e' stata presignata/caricata
RECEIVED           tutte le parti della fase sono presenti nello storage
QUEUED             job asincrono della fase accodato
PROCESSING         worker asincrono della fase in esecuzione
COMPLETED          fase terminata con successo
FAILED_RETRYABLE   errore temporaneo, retry ammesso
FAILED_FINAL       errore definitivo, serve intervento/nuova ingestion
```

Transizioni Core ammesse nel flusso corrente:

```text
PENDING -> RECEIVING
  prima parte Core presignata.

RECEIVING -> RECEIVING
  altre parti Core vengono presignate o confermate.

RECEIVING -> RECEIVED
  tutte le parti Core dichiarate sono state confermate via HEAD.

PENDING/RECEIVING/RECEIVED -> QUEUED
  complete-core accettata dopo verifica di tutte le parti Core attese.

QUEUED -> PROCESSING
  worker Celery prende in carico la Core Ingestion.

PROCESSING -> COMPLETED
  Trip materializzato con successo.

PROCESSING -> FAILED_RETRYABLE
  errore temporaneo durante download blob Core, decompressione o scrittura DB.

FAILED_RETRYABLE -> PROCESSING
  retry Celery o nuovo tentativo operativo.

PROCESSING/FAILED_RETRYABLE -> FAILED_FINAL
  esauriti i retry o schema non recuperabile.
```

Transizioni Raw nel flusso corrente:

```text
PENDING -> RECEIVING
  prima parte sensor_windows presignata.

RECEIVING -> RECEIVED
  tutte le parti Raw dichiarate sono state confermate.

RECEIVED -> QUEUED
  complete-raw accettata e HarJob finale creato.

QUEUED -> PROCESSING
  worker Celery prende in carico l'HAR finale.

PROCESSING -> COMPLETED
  HAR finale completato: segmenti scritti, Trip arricchito.

PROCESSING -> FAILED_RETRYABLE
  errore temporaneo durante lettura object storage, decompressione o pipeline.

PROCESSING/FAILED_RETRYABLE -> FAILED_FINAL
  payload raw invalido o retry esauriti.

PENDING -> COMPLETED
  caso valido quando non esistono raw attesi.
```

Transizioni da evitare:

```text
COMPLETED -> RECEIVING
  significherebbe riaprire una fase gia' chiusa.

FAILED_FINAL -> QUEUED
  richiede un'operazione amministrativa esplicita, non un retry automatico.

COMPLETED -> PROCESSING
  avrebbe senso solo con un job HAR di ricalcolo versionato, non con il flusso base.

raw_status -> RECEIVED quando core_status non e' COMPLETED
  renderebbe il Raw una scorciatoia impropria per creare o validare il viaggio.
```

### Dominio (PostGIS) — invariato e leggero

```text
Trip, GpsPoint(geography), StateTransition, MobilitySegment, SignificantPlace, HarJob
SensorWindow  -> SOLO metadata + object_key + label, MAI la matrice grezza
```

Nota sul modello `SensorWindow`: il campo `matrix` esiste ancora per compatibilita'
con il flusso legacy, ma nel percorso nuovo non deve essere popolato con la
matrice raw. Il campo utile per l'evoluzione e' `object_key`, che permette di
tenere in Postgres solo un riferimento al blob. La rimozione o deprecazione
formale di `matrix` va fatta in una migrazione separata, quando gli endpoint
legacy non saranno piu' usati dal mobile.

---

## Mobile: SyncJob Locale

Tabella nel DB locale (Drift) per disaccoppiare lo stato viaggio dallo stato
sync.

```text
SyncJob
  id
  local_session_id
  remote_ingestion_id
  core_status       (PENDING | PACKAGING | UPLOADING | WAITING_PROCESSING |
                     COMPLETED | FAILED_RETRYABLE | FAILED_FINAL)
  raw_status        (stesso vocabolario locale, ma fase secondaria)
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

Questa mappa vale per lo stato principale, cioe' `core_status`. `raw_status`
e' disponibile come dettaglio secondario: puo' indicare che i sensori raw sono
ancora in upload o hanno fallito, senza togliere dal diario un viaggio il cui
Core e' gia' completato.

Regola importante della coda: `raw_status` puo' rendere claimable un job solo
quando `core_status=COMPLETED`. Se il Core e' `FAILED_FINAL`, il Raw pendente
non deve "risvegliare" il job.

Il pulsante Stop non dichiara piu' "sincronizzato con successo": dice che il
viaggio e' salvato localmente e che la sincronizzazione prosegue in background.

Quando il backend Core e' in `QUEUED`, `PROCESSING` o `FAILED_RETRYABLE`, il
mobile non ricarica i blob Core e non richiama `complete-core`: resta in polling
con `core_status=WAITING_PROCESSING`. Se il backend Core arriva a
`FAILED_FINAL`, il job locale diventa `core_status=FAILED_FINAL`.

### Ciclo Di Vita Del SyncJob

```text
PENDING
  Job creato allo Stop. Nessuna garanzia che la rete sia disponibile.

PACKAGING
  Il client legge SQLite, costruisce i JSON, comprime gzip, calcola sha256 e
  size. Questa fase e' locale e puo' fallire per spazio disco o dati corrotti.

UPLOADING
  Esiste o viene creata una remote_ingestion_id. Il client carica solo le parti
  mancanti secondo `GET status`. Prima carica le parti Core; dopo Core
  completato carica le parti Raw.

WAITING_PROCESSING
  `complete-core` e' stata accettata. Il client non deve piu' fare PUT Core;
  deve solo pollare lo stato backend finche' `core_status=COMPLETED`.

COMPLETED
  Il Core ha raggiunto `COMPLETED` e il Raw e' `RECEIVED` o `COMPLETED`.
  I file temporanei locali del pacchetto possono essere eliminati.

FAILED_RETRYABLE
  Errore temporaneo. Il job resta claimable dopo `next_retry_at`.

FAILED_FINAL
  Il client ha esaurito i tentativi o il backend ha dichiarato fallimento finale.
  Serve azione manuale o una futura policy di "reset job".
```

La coda deve essere rientrante: se `kick()` viene chiamato piu' volte mentre un
processamento e' in corso, una sola esecuzione deve lavorare. Questa regola evita
due upload concorrenti dello stesso job, due `complete` ravvicinate o due timer
di polling che si pestano i piedi.

### Regole Di Retry Mobile

Il retry mobile deve distinguere tre classi di errore:

```text
Errore locale
  Esempi: impossibile leggere SQLite, impossibile scrivere file temporaneo,
  gzip fallito, JSON locale non valido.
  Azione: FAILED_RETRYABLE fino a maxAttempts; poi FAILED_FINAL.

Errore di rete / storage
  Esempi: timeout presign, timeout PUT, 5xx storage, URL scaduto.
  Azione: retry con backoff. Se il PUT puo' essere arrivato ma la risposta e'
  persa, il prossimo giro deve interrogare `GET status` e poi rifare confirm o
  upload solo se la parte risulta ancora mancante.

Errore backend semantico
  Esempi: 401 token non valido, 409 checksum diverso, 422 kind non valido,
  FAILED_FINAL sullo status.
  Azione: non bruciare tentativi per 401 prima del login; per conflitti reali,
  fermare il job e mostrare errore.
```

Backoff consigliato operativo:

```text
tentativo 1: immediato
tentativo 2: 10 s
tentativo 3: 30 s
tentativo 4: 2 min
tentativo 5: 10 min
oltre: FAILED_FINAL o policy manuale
```

In futuro si puo' aggiungere jitter casuale leggero (es. +/-20%) se molti client
riprendono insieme dopo un outage, ma per il profilo da ~1000 utenti non e' il
primo collo di bottiglia.

---

## Formati

```text
Core inline JSON:
  gps_points               punti GPS (UTC, WGS84, speed m/s, accuracy m)
  state_transitions        timeline decisionale FSM
  expected_raw_parts       dichiarazione delle parti raw attese
  core_payload_sha256      hash stabile del JSON Core

Raw object storage:
  sensor_windows_part_*.bin.gz   finestre 500x6 float32, formato MDHARW1
```

Il Core nuovo non viene scritto come file temporaneo gzip: e' inviato inline a
Django per materializzare rapidamente il `Trip`. Solo il Raw pesante passa da
file temporaneo gzip e object storage.

### Schema Logico Dei File

Core inline:

```json
{
  "client_session_id": "local-session-uuid",
  "schema_version": 1,
  "started_at": "2026-06-12T10:00:00Z",
  "ended_at": "2026-06-12T10:35:00Z",
  "expected_raw_parts": { "sensor_windows": 3 },
  "gps_points": [
    {
      "timestamp": "2026-06-12T10:01:05.123Z",
      "latitude": 45.4642,
      "longitude": 9.19,
      "speed_mps": 1.4,
      "accuracy_meters": 8.0
    }
  ],
  "state_transitions": [
    {
      "timestamp": "2026-06-12T10:02:00.000Z",
      "from_state": "POTENTIAL_MOTION",
      "to_state": "ACTIVE_TRACKING",
      "reason": "gps_speed_confirmed",
      "sigma": 0.42,
      "speed_mps": 2.1
    }
  ],
  "core_payload_sha256": "..."
}
```

`sensor_windows_part_0001.bin.gz`, dopo gunzip:

```text
magic[8]      = MDHARW1\0
window_count  = uint32 little-endian

per ogni finestra:
  start_us       int64 little-endian
  end_us         int64 little-endian
  frequency_hz   uint32 little-endian
  sample_count   uint32 little-endian
  channel_count  uint32 little-endian
  samples        float32 little-endian, row-major, 6 canali
```

Regole di validazione consigliate:

```text
- ogni file raw gzip deve decomprimersi in payload binario valido;
- magic deve essere MDHARW1\0;
- i timestamp devono essere parseabili e in ordine non decrescente per file;
- `gps_points` deve scartare righe senza latitude/longitude;
- `sensor_windows` deve dichiarare sample_count coerente con la dimensione blob;
- sample_rate_hz deve essere positivo;
- channel_count deve essere 6;
- sequence parte da 1 ed e' continua per ogni kind;
- una parte vuota non va generata: se un kind non ha dati, non entra negli
  expected parts della sua fase.
```

Il backend mantiene un fallback JSON legacy per payload storici o client non
aggiornati. Nel flusso mobile attuale, pero', i nuovi raw sono binari.

---

## Cosa Fa Celery

```text
process_trip_ingestion(ingestion_id):
  1. carica TripIngestion, verifica che il Core non sia gia' COMPLETED
  2. core_status -> PROCESSING
  3. legge blob gps + transitions
  4. BEGIN transaction.atomic():
       get_or_create(Trip by client_session_id)
       bulk_create(GpsPoint, ignore_conflicts)
       bulk_create(StateTransition, ignore_conflicts)
       ingestion.trip = Trip
       core_status -> COMPLETED
     COMMIT
  5. il Raw resta fase separata: viene accodata da complete-raw.

process_trip_har_final(job_id, ingestion_id):
  1. claim idempotente di TripIngestion + HarJob
  2. raw_status -> PROCESSING
  3. legge le parti sensor_windows da object storage
  4. gunzip
  5. decodifica MDHARW1 in finestre 500x6 float32
  6. esegue pipeline HAR finale:
       CNN extractor -> GRU batchata -> correzione GPS -> segmentazione
  7. scrive MobilitySegment e VirtualStopInterval
  8. Trip.status -> PROCESSED
  9. raw_status -> COMPLETED
  10. accoda mining luoghi significativi
  11. cleanup raw solo se HAR_CLEANUP_ENABLED=true
  12. on FAILURE:
       salva error, raw_status -> FAILED_RETRYABLE / FAILED_FINAL
       NON cancella i blob (servono al retry/debug)
```

Le matrici grezze restano in object storage finche' la policy di retention non
abilita il cleanup event-driven post-HAR (D9).

### Atomicita E Retry Del Worker

`process_trip_ingestion` deve essere progettato come task almeno-once: Celery
puo' eseguirlo due volte se il worker muore dopo aver scritto su DB ma prima di
acknowledgare il task. Per questo:

```text
- Trip nasce con get_or_create(client_session_id);
- GpsPoint usa unique(trip, timestamp);
- StateTransition usa unique(trip, timestamp, to_state);
- bulk_create usa ignore_conflicts;
- core_status=COMPLETED fa da guardia per saltare rielaborazioni.
```

La transazione atomica deve contenere solo operazioni DB leggere. Il download da
object storage, la decompressione e la decodifica raw avvengono fuori dalla
parte critica. Le sensor window non entrano nel database transazionale.

Errori retryable tipici:

```text
- object storage temporaneamente non raggiungibile;
- blob presente ma GET fallisce per timeout;
- database temporaneamente saturo o lock timeout;
- worker riavviato durante processing.
```

Errori finali tipici:

```text
- gzip corrotto in modo ripetibile;
- JSON non parseabile;
- schema mancante in modo non recuperabile;
- timestamp non parseabile;
- ingestion senza parti richieste ma marcata complete.
```

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

Dettagli da non perdere:

```text
Bearer token
  Ogni endpoint deve risolvere request.auth.user_id e filtrare sempre per user.
  Non basta controllare l'id ingestion numerico.

Presigned URL
  Deve scadere in fretta (default 900s). Se scade, il client richiede un nuovo
  presign per la stessa parte.

Checksum
  sha256 nei metadata S3 non e' una garanzia crittografica assoluta contro un
  attaccante con credenziali valide, ma e' sufficiente per rilevare upload
  parziali, retry sbagliati e mismatch applicativi.

Limite dimensione
  `INGESTION_MAX_PART_BYTES` protegge da parti eccessive. Va mantenuto coerente
  con il budget mobile di chunking.

Object key
  Il client non sceglie liberamente object_key. Il backend lo deriva da ingestion
  e parte. Questo evita scritture fuori dal prefisso assegnato.
```

---

## Performance, Capacita E Colli Di Bottiglia

Il design ottimizza prima la stabilita' del sistema, poi la latenza percepita.
Le grandezze da osservare sono:

```text
Tempo locale:
  Stop -> SyncJob creato
  Stop -> packaging completato

Tempo upload:
  packaging completato -> tutte le parti confermate
  tempo medio PUT per MB
  numero parti ritentate

Tempo backend:
  complete-core accettata -> core_status QUEUED
  core_status QUEUED -> PROCESSING
  core_status PROCESSING -> COMPLETED
  core_status COMPLETED -> raw_status RECEIVED/COMPLETED

Volume:
  byte totali gzip per viaggio
  byte sensor_windows / byte totali
  numero window per minuto di viaggio
```

Budget indicativi per il profilo attuale:

```text
Stop -> SyncJob creato:             < 200 ms
Packaging viaggio breve:            < 2 s
Packaging viaggio lungo:            puo' crescere con le window, da misurare
Presign/confirm singola chiamata:    < 500 ms su rete buona
Celery materializzazione leggera:    < 5 s per viaggi normali
```

Il punto piu' costoso oggi e' quasi sempre il payload HAR, per tre motivi:

```text
- molte righe: 500 campioni x 9 canali x finestra;
- JSON verbose prima della compressione;
- upload mobile sensibile a rete, batteria e radio.
```

Migliorie future ordinate per impatto sulla velocita':

```text
1. separare upload core (GPS/transitions) da upload raw HAR;
2. upload parallelo controllato con concurrency 2-4;
3. batch presign e batch confirm;
4. upload streaming da file invece di readAsBytes;
5. formato binario float32 per sensor windows;
6. packaging incrementale durante la corsa.
```

Queste migliorie non cambiano l'invariante principale: i byte pesanti non
devono attraversare Django e le matrici raw non devono entrare in Postgres.

---

## Osservabilita Minima

Senza metriche questo sistema e' difficile da debuggare, perche' un viaggio puo'
essere "salvato localmente" ma ancora non visibile nel dominio backend. Servono
almeno log strutturati e contatori.

Log mobile consigliati:

```text
sync.job.created
  local_session_id, started_at, ended_at

sync.package.created
  local_session_id, parts_count, total_size_bytes, gps_count,
  transition_count, sensor_window_count

sync.part.upload.started / completed / failed
  local_session_id, ingestion_id, kind, sequence, size_bytes, sha256_prefix

sync.job.completed / failed
  local_session_id, ingestion_id, attempts, last_error
```

Log backend consigliati:

```text
ingestion.created
  user_id, ingestion_id, client_session_id, expected_core_parts,
  expected_raw_parts

ingestion.part.presigned
  ingestion_id, phase, kind, sequence, size_bytes

ingestion.part.confirmed
  ingestion_id, phase, kind, sequence, size_bytes

ingestion.core.completed
  ingestion_id, trip_id, received_core_parts_count, total_size_bytes

ingestion.raw.received
  ingestion_id, received_raw_parts_count, total_size_bytes

ingestion.processing.started / succeeded / failed
  ingestion_id, trip_id, gps_points, transitions, duration_ms, error
```

Metriche minime:

```text
counter ingestion_created_total
counter ingestion_part_confirmed_total{kind}
counter ingestion_failed_total{reason}
gauge   ingestion_in_progress{status}
histogram ingestion_upload_bytes{kind}
histogram ingestion_processing_duration_seconds
histogram mobile_packaging_duration_seconds
histogram mobile_upload_duration_seconds
```

Alert utili anche in un progetto piccolo:

```text
- molte ingestion ferme in RECEIVING da piu' di 24h;
- molte ingestion in QUEUED con worker Celery attivo ma backlog crescente;
- spike di FAILED_FINAL;
- bucket object storage che cresce oltre soglia prevista;
- percentuale alta di parti con retry.
```

---

## Failure Mode E Recupero

```text
Caso: app chiusa subito dopo Stop
  Stato: sessione chiusa in SQLite, SyncJob forse creato.
  Recupero: all'avvio, resumeSync deve processare SyncJob pendenti.

Caso: app chiusa durante packaging
  Stato: SyncJob PACKAGING, file temporanei forse incompleti.
  Recupero: nuovo packaging da SQLite; la directory temporanea puo' essere
  cancellata e ricreata.

Caso: risposta di POST /api/ingestion/trips persa
  Stato: TripIngestion creata ma mobile non lo sa.
  Recupero: nuovo POST /api/ingestion/trips con stesso client_session_id ritorna
  stessa ingestion.

Caso: PUT riuscito ma risposta persa
  Stato: oggetto forse presente, parte non confermata.
  Recupero: il client rifara' presign/PUT/confirm oppure confirm; backend usera'
  HEAD per stabilire la verita'.

Caso: confirm riuscita ma risposta persa
  Stato: part.received_at valorizzato.
  Recupero: nuovo confirm ritorna ALREADY_RECEIVED o status mostra parte ricevuta.

Caso: complete-core riuscita ma risposta persa
  Stato: core_status QUEUED o oltre.
  Recupero: GET status; il mobile passa a core_status WAITING_PROCESSING.

Caso: raw upload fallisce dopo Core completato
  Stato: core_status COMPLETED, raw_status locale FAILED_RETRYABLE o FAILED_FINAL.
  Recupero: il viaggio resta visibile; il retry successivo lavora solo sul Raw.

Caso: worker Celery spento
  Stato: core_status resta QUEUED.
  Recupero: avviare worker; nessun re-upload necessario.

Caso: worker fallisce su errore temporaneo
  Stato: core_status FAILED_RETRYABLE e retry Celery.
  Recupero: il mobile resta in WAITING_PROCESSING finche' backend non cambia stato.

Caso: schema file non valido
  Stato: core_status FAILED_FINAL.
  Recupero: visibile in UI come errore finale; serve bugfix o reset amministrativo.

Caso: token scaduto
  Stato: SyncJob locale invariato.
  Recupero: non bruciare retry prima del nuovo login; dopo login resumeSync riparte.
```

---

## Checklist Di Verifica End-To-End

Per dichiarare sano il flusso, non basta vedere la snackbar mobile. Va controllata
la catena completa:

```text
1. Start tracking crea AcquisitionSession con UUID locale.
2. Durante tracking vengono scritti GpsPoints, StateTransitions e SensorWindows.
3. Stop valorizza endedAt e crea un SyncJob PENDING.
4. resume/kick porta il job a PACKAGING.
5. La directory temporanea contiene file .bin.gz raw con sha256 e size coerenti.
6. POST /api/ingestion/trips/core materializza il Core inline.
7. Trip esiste, appartiene all'utente giusto e ha client_session_id corretto.
8. GpsPoint e StateTransition sono presenti senza duplicati.
9. Solo dopo Core COMPLETED, le parti Raw hanno presign, PUT e confirm.
10. complete-raw porta raw_status a QUEUED.
11. Celery porta raw_status a PROCESSING e poi COMPLETED.
12. Le sensor window raw sono presenti nel bucket.
13. Le matrici raw non vengono salvate in Postgres.
14. Il SyncJob locale diventa COMPLETED quando Core e Raw sono chiusi.
```

Test negativi essenziali:

```text
- doppio Stop non duplica SyncJob;
- doppio POST /api/ingestion/trips non duplica TripIngestion;
- doppia confirm non duplica TripIngestionPart;
- checksum diverso sulla stessa parte confermata produce 409;
- complete-core con parte Core mancante produce 409;
- complete-raw prima di Core COMPLETED produce 409;
- presign di una parte non dichiarata produce 409;
- worker rilanciato non duplica GPS/transizioni;
- ingestion di un altro utente non e' accessibile con id numerico.
```

---

## Diagramma Di Sequenza Completo

Questo diagramma usa una sintassi compatibile con <https://sequencediagram.org>.
Va copiato senza il blocco markdown e incollato nell'editor del sito.

```text
title Upload asincrono viaggio - Core Ingestion + Raw Sensor Ingestion

participant Utente
participant HomePage
participant AcquisitionCubit
participant AcquisitionRepository
participant SensorRuntime
participant SQLite
participant TripSyncQueue
participant AuthRepository
participant TripPackageBuilder
participant FileSystem
participant TripIngestionHttpApi
participant DjangoIngestionApi
participant Postgres
participant ObjectStorage
participant CeleryBroker
participant CeleryWorker
participant HarWorkerFuture

Utente->HomePage: Tap Stop
HomePage->AcquisitionCubit: stopTracking()
AcquisitionCubit->AcquisitionRepository: stopTracking()
AcquisitionRepository->SensorRuntime: stop()
SensorRuntime-->AcquisitionRepository: sensori fermati
AcquisitionRepository->SQLite: endSession(sessionId, endedAt)
SQLite-->AcquisitionRepository: sessione chiusa
AcquisitionRepository->SQLite: createSyncJobIfAbsent(sessionId)
SQLite-->AcquisitionRepository: SyncJob(PENDING)
AcquisitionRepository-->AcquisitionCubit: ritorno immediato
AcquisitionCubit-->HomePage: snapshot idle
HomePage-->Utente: viaggio salvato, sync in background

note over AcquisitionRepository,TripSyncQueue: Lo Stop non aspetta rete, packaging o backend.
AcquisitionRepository->TripSyncQueue: kick() fire-and-forget

TripSyncQueue->AuthRepository: accessToken
alt token assente
  AuthRepository-->TripSyncQueue: null
  TripSyncQueue-->TripSyncQueue: esce senza bruciare retry
else token disponibile
  AuthRepository-->TripSyncQueue: Bearer token
  TripSyncQueue->SQLite: claimableSyncJobs(now)
  SQLite-->TripSyncQueue: lista SyncJob attivi

  loop per ogni SyncJob pronto
    TripSyncQueue->SQLite: updateSyncJob(core_status=PACKAGING, lastError=null)
    TripSyncQueue->TripPackageBuilder: build(localSessionId)
    TripPackageBuilder->SQLite: findSession + gps + transitions + sensor windows
    SQLite-->TripPackageBuilder: dati locali del viaggio
    TripPackageBuilder->FileSystem: write sensor_windows_part_N.bin.gz
    FileSystem-->TripPackageBuilder: file gzip + sha256 + sizeBytes
    TripPackageBuilder-->TripSyncQueue: TripPackage(corePayload inline, rawParts, expectedRawParts)

    alt pacchetto vuoto
      TripSyncQueue->SQLite: updateSyncJob(core_status=COMPLETED, raw_status=COMPLETED)
    else nessun Core payload
      TripSyncQueue->SQLite: updateSyncJob(core_status=FAILED_FINAL, lastError)
    else pacchetto con Core
      TripSyncQueue->SQLite: updateSyncJob(core_status=UPLOADING)
      TripSyncQueue->TripIngestionHttpApi: postCoreInline(corePayload)
      TripIngestionHttpApi->DjangoIngestionApi: POST /api/ingestion/trips/core
      DjangoIngestionApi->Postgres: get_or_create TripIngestion(user, client_session_id)
      DjangoIngestionApi->Postgres: materializza Trip + GPS + transizioni + path
      DjangoIngestionApi-->TripIngestionHttpApi: ingestion_id + trip_id + core_status=COMPLETED
      TripIngestionHttpApi-->TripSyncQueue: InlineCoreResult
      TripSyncQueue->SQLite: updateSyncJob(core_status=COMPLETED, remoteTripId)
    end
  end
end

TripSyncQueue->TripIngestionHttpApi: getStatus(ingestionId) dopo nextRetryAt
TripIngestionHttpApi->DjangoIngestionApi: GET /api/ingestion/trips/{ingestion_id}
DjangoIngestionApi->Postgres: load phase statuses
Postgres-->DjangoIngestionApi: core_status=COMPLETED + raw_status + trip_id
DjangoIngestionApi-->TripIngestionHttpApi: status Core completed
TripIngestionHttpApi-->TripSyncQueue: core completed
TripSyncQueue->SQLite: updateSyncJob(core_status=COMPLETED)

alt nessun Raw atteso o Raw gia RECEIVED/COMPLETED
  TripSyncQueue->SQLite: updateSyncJob(raw_status=COMPLETED)
  TripSyncQueue->FileSystem: delete temp package directory
  HomePage-->Utente: UI mostra viaggio sincronizzato
else Raw ancora da caricare
  TripSyncQueue->SQLite: updateSyncJob(raw_status=UPLOADING)
  loop per ogni parte Raw mancante
    TripSyncQueue->TripIngestionHttpApi: presignPart(sensor_windows, sequence, sha256, size)
    TripIngestionHttpApi->DjangoIngestionApi: POST /api/ingestion/trips/{id}/parts/presign
    DjangoIngestionApi->Postgres: verifica parte dichiarata in expected_raw_parts
    DjangoIngestionApi->ObjectStorage: generate presigned PUT URL
    ObjectStorage-->DjangoIngestionApi: upload_url
    DjangoIngestionApi-->TripIngestionHttpApi: object_key + upload_url + headers
    TripIngestionHttpApi->FileSystem: read raw gzip bytes
    FileSystem-->TripIngestionHttpApi: bytes
    TripIngestionHttpApi->ObjectStorage: PUT upload_url (raw bytes + metadata sha256)
    ObjectStorage-->TripIngestionHttpApi: 2xx
    TripIngestionHttpApi->DjangoIngestionApi: POST /api/ingestion/trips/{id}/parts/confirm
    DjangoIngestionApi->ObjectStorage: HEAD object_key
    ObjectStorage-->DjangoIngestionApi: ContentLength + metadata sha256
    DjangoIngestionApi->Postgres: set TripIngestionPart.received_at
    DjangoIngestionApi->Postgres: registra Raw part confermata
    DjangoIngestionApi-->TripIngestionHttpApi: RECEIVED or ALREADY_RECEIVED
    TripIngestionHttpApi-->TripSyncQueue: raw part confermata
  end

  TripSyncQueue->TripIngestionHttpApi: completeRawIngestion(ingestionId, totalParts)
  TripIngestionHttpApi->DjangoIngestionApi: POST /api/ingestion/trips/{id}/complete-raw
  DjangoIngestionApi->Postgres: verifica core_status=COMPLETED
  DjangoIngestionApi->Postgres: verifica tutte le parti Raw confermate
  DjangoIngestionApi->Postgres: raw_status=QUEUED + crea HarJob
  DjangoIngestionApi->CeleryBroker: enqueue process_trip_har_final
  DjangoIngestionApi-->TripIngestionHttpApi: 202 raw_status=QUEUED
  TripIngestionHttpApi-->TripSyncQueue: raw accodato
  TripSyncQueue->SQLite: updateSyncJob(raw_status=WAITING_PROCESSING)
  CeleryWorker->CeleryBroker: consume process_trip_har_final
  CeleryWorker->ObjectStorage: GET sensor_windows_part_N.bin.gz
  CeleryWorker->CeleryWorker: gunzip + decode MDHARW1 + CNN/GRU
  CeleryWorker->Postgres: scrive segmenti, Trip.status=PROCESSED, raw_status=COMPLETED
  TripSyncQueue->TripIngestionHttpApi: getStatus(ingestionId)
  TripIngestionHttpApi-->TripSyncQueue: raw_status=COMPLETED
  TripSyncQueue->SQLite: updateSyncJob(raw_status=COMPLETED)
  TripSyncQueue->FileSystem: delete temp package directory
  HomePage-->Utente: UI mostra viaggio sincronizzato
end

note over DjangoIngestionApi,HarWorkerFuture: Futuro HAR: raw_status RECEIVED -> QUEUED -> PROCESSING -> COMPLETED, poi cleanup raw.
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

### Fase 4 — HAR su blob + cleanup event-driven

```text
- process_trip_har_final legge i blob da object storage
- decodifica raw binario MDHARW1
- esegue pipeline CNN+GRU
- scrive segmenti e porta raw_status=COMPLETED
- cancellazione raw dopo HAR success      <-- DISATTIVATA finche' HAR_CLEANUP_ENABLED=false
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
