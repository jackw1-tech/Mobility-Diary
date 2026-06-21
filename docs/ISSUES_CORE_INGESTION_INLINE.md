# Issue verticali - Core Ingestion inline sincrona

Derivate da `PRD_CORE_INGESTION_INLINE.md`.

Le slice sono tracer bullet in ordine di dipendenza. La prima rende esplicito il
nuovo modello di stato/schema; le successive cambiano il comportamento end-to-end
senza perdere la compatibilita' legacy.

## Issue 1 - State model: distinguere fase core/raw da modalita' di caricamento

**Blocked by**: None - can start immediately

**User stories covered**: 14, 15, 16, 17, 20, 21, 24, 25

## What to build

Rendere esplicito nel sistema che `core_status` e `raw_status` descrivono la fase
dell'Ingestione del Viaggio, mentre una nuova modalita' descrive come il Core e'
stato ricevuto: vecchio caricamento a parti oppure Core Ingestion inline.

Questa slice non deve ancora cambiare il percorso mobile principale. Deve solo
preparare schema, stati osservabili e test, cosi' le slice successive possano
implementare la POST core senza ambiguita'.

## Acceptance criteria

- [ ] Backend: `TripIngestion` ha i nuovi campi persistenti per `core_payload_sha256`, `core_payload_size_bytes` e `core_ingestion_mode`.
- [ ] Backend: gli stati esistenti `core_status` e `raw_status` restano la source of truth delle fasi; non viene introdotto un nuovo phase status solo per inline core.
- [ ] Backend: le ingestion esistenti migrano come `LEGACY_PARTS` senza rompere il vecchio flusso presigned.
- [ ] Backend: la status API espone `core_ingestion_mode` e un segnale `map_available` derivato.
- [ ] Mobile: `SyncJob` ha i nuovi campi `corePayloadSha256`, `corePayloadSizeBytes` e `coreMapAvailable`.
- [ ] Mobile: la migration Drift aggiorna lo schema senza perdere job esistenti.
- [ ] Mobile: il gate mappa usa `coreStatus=COMPLETED`, `remoteTripId != null` e `coreMapAvailable=true`.
- [ ] Test backend e mobile coprono migrazioni, default legacy e gate mappa negativo quando `coreMapAvailable=false`.

## Issue 2 - Backend: Core Ingestion inline completa via API

**Blocked by**: Issue 1

**User stories covered**: 4, 5, 6, 7, 8, 12, 14, 15, 16, 17, 20, 21, 22, 23, 26, 27

## What to build

Implementare il percorso backend primario `POST /api/ingestion/trips/core`.
L'endpoint riceve metadata, GPS points, state transitions, `expected_raw_parts`
e `core_payload_sha256`, poi materializza sincronicamente il Core dentro la
request HTTP.

Il risultato verificabile di questa slice e' che un client autenticato possa
sincronizzare un Viaggio piccolo in una sola request e ottenere subito
`trip_id`, conteggi, distanza e `map_available`, senza object storage, Celery o
polling nel path felice.

## Acceptance criteria

- [ ] `POST /api/ingestion/trips/core` e' autenticato con Bearer token mobile e filtrato per utente.
- [ ] Il body inline usa la stessa shape dei JSON core legacy per GPS points e state transitions.
- [ ] Il body intero decodificato e' limitato a 1 MB; oltre il limite risponde `413`.
- [ ] Il backend verifica `core_payload_sha256`; mismatch del payload risponde `400`.
- [ ] Stesso utente e stesso `client_session_id` con stesso hash e' idempotente.
- [ ] Stesso utente e stesso `client_session_id` con hash diverso risponde `409`.
- [ ] Core vuoto, senza GPS points e senza state transitions, risponde `400`.
- [ ] Core con solo GPS o solo state transitions puo' completare.
- [ ] Il path felice inline imposta `core_ingestion_mode=INLINE` e `core_status=COMPLETED`.
- [ ] `raw_status` diventa `PENDING` se `expected_raw_parts` contiene raw, altrimenti `COMPLETED`.
- [ ] Il Trip viene creato/recuperato in modo idempotente e la Traiettoria del Viaggio viene derivata dai GPS ordinati.
- [ ] `map_available=true` solo quando la traiettoria e' davvero disponibile; GPS insufficienti completano il core ma restituiscono `map_available=false`.
- [ ] L'endpoint non crea core `TripIngestionPart` e non legge/scrive object storage.
- [ ] Stati legacy `QUEUED`, `PROCESSING` e `FAILED_FINAL` seguono la semantica definita dal PRD.
- [ ] Test API coprono happy path, idempotenza, conflitti, limiti, user isolation e casi senza mappa.

## Issue 3 - Mobile: SyncJob usa POST core inline

**Blocked by**: Issue 1, Issue 2

**User stories covered**: 1, 2, 4, 5, 6, 7, 9, 19, 24, 25, 28

## What to build

Cambiare il percorso mobile nuovo in modo che il Core non venga piu' spedito
come `gps_points.json.gz` e `state_transitions.json.gz` via presigned upload.
Il SyncJob deve costruire un JSON inline deterministico, calcolare
`corePayloadSha256`, chiamare `POST /api/ingestion/trips/core`, salvare
`remoteIngestionId`, `remoteTripId` e `coreMapAvailable`, poi aggiornare lo stato
locale del core a completed.

## Acceptance criteria

- [ ] Il builder mobile produce un payload core inline deterministico con GPS points e state transitions nella shape legacy.
- [ ] Il mobile calcola `corePayloadSha256` sul JSON core deterministico prima di inserire il campo hash.
- [ ] Nel path nuovo non vengono creati gzip core per GPS points e state transitions.
- [ ] La coda usa `PACKAGING` per creare payload/hash e `UPLOADING` per la POST core inline.
- [ ] La coda salva `remoteIngestionId`, `remoteTripId`, `corePayloadSha256`, `corePayloadSizeBytes` e `coreMapAvailable` dalla risposta.
- [ ] Se la risposta indica core completato e `map_available=true`, la Home puo' mostrare il bottone mappa.
- [ ] Se la risposta indica core completato ma `map_available=false`, il Viaggio resta sincronizzato ma la mappa non viene resa disponibile.
- [ ] Errori temporanei mantengono retry/backoff esistente e non duplicano il Viaggio.
- [ ] Test di SyncJob con API fake coprono successo, idempotenza, errore, e gate mappa.

## Issue 4 - Raw Sensor Ingestion continua dopo Core Inline

**Blocked by**: Issue 1, Issue 2, Issue 3

**User stories covered**: 3, 10, 11, 13, 15, 21, 24, 25

## What to build

Completare il comportamento "core subito, raw dopo". Dopo la risposta positiva
della POST core inline, lo stesso SyncJob deve continuare a caricare i raw
`sensor_windows` con il flusso presigned esistente, usando l'ingestion id
ritornato dalla POST core.

La riuscita o il fallimento retryable del raw non deve tornare a bloccare il
Viaggio Sincronizzato o la Traiettoria del Viaggio gia' resa disponibile dal
core.

## Acceptance criteria

- [ ] La POST core dichiara `expected_raw_parts` e il backend inizializza correttamente `raw_status`.
- [ ] Se esistono raw, dopo core completed il mobile continua con presign/PUT/confirm/complete-raw sulla stessa TripIngestion.
- [ ] Se non esistono raw, il SyncJob chiude anche `rawStatus=COMPLETED`.
- [ ] Se il raw fallisce temporaneamente dopo core completed, il core resta completed e il `remoteTripId` resta disponibile.
- [ ] Il retry raw riparte dalla fase raw senza rifare core inline inutilmente.
- [ ] Il backend continua a rifiutare `complete-raw` finche' il core non e' completed.
- [ ] Test backend/mobile coprono raw presente, raw assente e raw failure dopo core success.

## Issue 5 - Legacy compatibility e hardening operativo

**Blocked by**: Issue 1, Issue 2, Issue 3, Issue 4

**User stories covered**: 18, 19, 25, 26

## What to build

Rafforzare il bordo tra nuovo Core Ingestion inline e vecchio Core Ingestion a
parti. Gli endpoint legacy devono restare funzionanti per client vecchi, ma il
mobile nuovo non deve usarli per GPS/state. La documentazione deve rendere
chiaro quali stati appartengono al path inline, quali al path legacy e quali al
raw.

## Acceptance criteria

- [ ] Il vecchio flusso presigned core continua a funzionare per ingestion `LEGACY_PARTS`.
- [ ] Il mobile nuovo non chiama presign/confirm/complete-core per GPS points o state transitions.
- [ ] Gli stati legacy `RECEIVING`, `RECEIVED`, `QUEUED`, `PROCESSING` restano coperti da test o casi espliciti.
- [ ] `FAILED_FINAL` core non viene riaperto automaticamente dalla POST inline.
- [ ] La status API rende chiaro mode, core status, raw status e disponibilita' mappa.
- [ ] PRD, ADR/report e script issue sono allineati con la semantica finale.
- [ ] Test di regressione coprono legacy core e nuovo inline core nello stesso sistema.
