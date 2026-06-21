# PRD - Core Ingestion inline sincrona

> Versione 1 - 2026-06-21.
> Riguarda l'Ingestione del Viaggio tra app Flutter e backend Django/PostGIS.
> Rispetta ADR 0001 e ADR 0002: una sola TripIngestion, stati core/raw
> separati, Core Ingestion inline come percorso primario, Raw Sensor Ingestion
> ancora via presigned object storage.

## Problem Statement

Oggi il Core Ingestion usa lo stesso protocollo pensato per i raw pesanti:
creazione ingestion, presign, PUT su object storage, confirm, complete-core,
Celery, polling. Questo e' affidabile, ma e' sproporzionato per GPS points e
state transitions, che nel caso osservato stanno nell'ordine di poche decine di
KB e comunque devono restare sotto payload piccoli.

Dal punto di vista dell'utente, dopo aver fermato un Viaggio il valore utile e'
vederlo comparire velocemente e poter aprire la Traiettoria del Viaggio su
mappa. Il flusso attuale paga troppi round trip e troppi passaggi asincroni
prima di rendere disponibile il trip_id, anche quando il Core e' piccolo.

Il sistema deve rendere il Core Ingestion piu' veloce e lineare senza perdere:
idempotenza, separazione tra core e raw, sicurezza per utente, compatibilita' con
i client vecchi, e il percorso presigned per Raw Sensor Ingestion.

## Solution

Il mobile nuovo usera' un endpoint primario:

`POST /api/ingestion/trips/core`

L'endpoint riceve in un unico body JSON il Core del Viaggio:

- metadata della sessione;
- `core_payload_sha256`;
- `gps_points`;
- `state_transitions`;
- `expected_raw_parts`.

Il backend materializza sincronicamente il Core nella request HTTP: valida il
payload, verifica la protezione hash, crea o recupera la TripIngestion tramite
`client_session_id`, crea o recupera il Trip, inserisce GPS points e state
transitions in modo idempotente, costruisce la LineString derivata, aggiorna
distanza e stato, marca `core_status=COMPLETED`, e restituisce subito
`trip_id`, conteggi, `distance_meters` e `map_available`.

La Raw Sensor Ingestion resta sul flusso presigned/object-storage esistente. Dopo
la risposta core, lo stesso SyncJob mobile puo' continuare nella stessa passata a
caricare `sensor_windows` via presign/PUT/confirm/complete-raw. Il valore
prodotto dal Core non aspetta il raw: un fallimento raw non deve nascondere il
Viaggio Sincronizzato ne' la sua mappa.

Gli endpoint presigned core esistenti restano come compatibilita' legacy per
client vecchi, ma non sono piu' il percorso evolutivo per il mobile nuovo.

## User Stories

1. As a mobile user, I want a stopped Viaggio to become synchronized quickly, so that I can see it in the app without waiting for raw upload.
2. As a mobile user, I want the map button to appear as soon as Core Ingestion has completed and a trip_id exists, so that I can inspect the Traiettoria del Viaggio immediately.
3. As a mobile user, I want raw sensor upload failures not to remove access to a synchronized Viaggio, so that a secondary enrichment failure does not block the core diary value.
4. As a mobile user, I want retries after temporary network problems to be safe, so that stopping a trip cannot create duplicate trips.
5. As a mobile user, I want a retry of the same session to return the same result, so that app restarts and flaky connectivity do not corrupt my diary.
6. As a mobile user, I want the app to reject impossible duplicate session data, so that a bug cannot overwrite one trip with different evidence.
7. As a mobile user, I want a Viaggio with enough GPS points to show a trajectory, so that I can understand where I moved.
8. As a mobile user, I want a Viaggio with only state transitions to still synchronize, so that lack of GPS does not make the whole trip disappear.
9. As a mobile user, I want the app to say that the trajectory is unavailable when GPS evidence is insufficient, so that the UI does not crash or show misleading maps.
10. As a mobile user, I want the app to keep uploading raw sensor evidence in the background after core completion, so that future enrichment can still happen.
11. As a mobile user, I want the raw upload to resume later if it fails, so that temporary storage or network failures are recoverable.
12. As a backend operator, I want Core Ingestion to avoid object storage for small core evidence, so that Django/PostGIS can complete the product-critical path in one request.
13. As a backend operator, I want Raw Sensor Ingestion to remain on presigned object storage, so that large raw payloads do not pass through Django or Postgres.
14. As a backend operator, I want one TripIngestion per mobile session, so that core and raw states are correlated in one lifecycle.
15. As a backend operator, I want `core_status` and `raw_status` to remain separate, so that the system can show a Viaggio as synchronized while raw is still pending.
16. As a backend operator, I want the inline core body to have a hard size limit, so that the endpoint cannot become an accidental large-upload channel.
17. As a backend operator, I want same-session/different-payload retries to conflict, so that materialized trips remain deterministic.
18. As a backend operator, I want legacy presigned core endpoints to continue working, so that older clients do not break during rollout.
19. As a backend operator, I want new clients to prefer inline core, so that future work is not split across two primary core paths.
20. As a backend operator, I want the inline endpoint response to include `map_available`, so that mobile does not need an immediate status poll to decide the UI.
21. As a backend operator, I want `expected_raw_parts` declared during inline core, so that the single TripIngestion knows whether raw is absent, pending, or ready for upload.
22. As a developer, I want the inline arrays to keep the same shape as the existing core JSON files, so that parsers, tests, and domain understanding do not fork.
23. As a developer, I want the path-building behavior to be reused, so that inline core and legacy core produce the same Traiettoria del Viaggio.
24. As a developer, I want the mobile sync queue to continue representing one local SyncJob, so that the local state machine stays understandable.
25. As a developer, I want tests at the API and sync-queue seams, so that behavior is verified from the outside rather than by coupling tests to helper internals.
26. As a developer, I want clear status codes for retry and conflict cases, so that mobile recovery logic is simple and deterministic.
27. As a developer, I want the endpoint to be filtered by Bearer-authenticated user, so that a client cannot affect or inspect another user's ingestion by id.
28. As a product stakeholder, I want the Core Ingestion path to be visibly faster, so that the map feature feels immediate after stopping a trip.

## Implementation Decisions

- The primary new API is `POST /api/ingestion/trips/core`.
- The endpoint is authenticated with the same mobile Bearer authentication used by the existing ingestion API.
- The endpoint is user-scoped: a `client_session_id` is unique per user, and all existing ingestion lookups are constrained to the authenticated user.
- The endpoint materializes Core Ingestion synchronously inside the HTTP request.
- The endpoint does not enqueue Celery on the happy path for inline core.
- The backend keeps a single TripIngestion lifecycle with separate `core_status` and `raw_status`.
- Inline Core Ingestion sets `core_status=COMPLETED` before returning a successful response.
- Inline Core Ingestion declares `expected_raw_parts` in the same request.
- If `expected_raw_parts` is empty, the backend initializes or keeps `raw_status=COMPLETED`.
- If `expected_raw_parts` contains sensor window parts, the backend initializes or keeps `raw_status=PENDING`.
- The Raw Sensor Ingestion path remains the existing presign/PUT/confirm/complete-raw flow.
- Existing presigned core endpoints remain available as legacy compatibility, but new mobile sync code should not use them for GPS points or state transitions.
- The inline request body uses the same record shape as the existing `gps_points` and `state_transitions` core JSON payloads.
- Inline core accepts a payload with GPS points only, state transitions only, or both.
- Inline core rejects an empty core payload with no GPS points and no state transitions.
- A Viaggio Sincronizzato is not identical to a map-ready Viaggio: `map_available` is true only when enough valid GPS evidence exists to derive a Traiettoria del Viaggio.
- The inline request body has a hard maximum of 1 MB measured on the whole decoded JSON body, metadata included.
- Requests above the 1 MB decoded-body limit return `413 Payload Too Large`.
- The mobile sends `core_payload_sha256` with the inline core request.
- The hash is computed on the deterministic UTF-8 JSON body before `core_payload_sha256` is inserted.
- The backend verifies the submitted hash by removing `core_payload_sha256`, rebuilding the same stable compact JSON representation, and comparing hashes.
- If the submitted hash does not match the received payload, the backend returns `400 Bad Request`.
- If the same user and `client_session_id` retry with the same hash, the endpoint is idempotent and returns the existing or newly converged result.
- If the same user and `client_session_id` retry with a different hash, the backend returns `409 Conflict`.
- If an existing inline/legacy ingestion has `core_status=COMPLETED`, the inline endpoint returns the existing `ingestion_id`, `trip_id`, `core_status`, `raw_status`, counts, `distance_meters`, and `map_available`.
- If an existing ingestion has `core_status=PENDING`, `RECEIVING`, `RECEIVED`, or `FAILED_RETRYABLE`, the inline endpoint may process the submitted payload and converge it to completed.
- If an existing ingestion has legacy `core_status=QUEUED` or `PROCESSING`, the inline endpoint returns the current state without starting a second materialization.
- If an existing ingestion has `core_status=FAILED_FINAL`, the inline endpoint returns `409 Conflict`; recovery requires a deliberate future path.
- A successful inline core response returns enough UI information to avoid an immediate status poll: `ingestion_id`, `trip_id`, `core_status`, `raw_status`, materialized counts, `distance_meters`, and `map_available`.
- The response also returns enough status for the same SyncJob to continue raw upload via existing raw endpoints.
- The backend stores a core-specific payload hash for conflict detection; it must not confuse this with raw part checksums.
- The backend should not create core TripIngestionPart rows for inline GPS/state evidence; those rows remain a legacy part-upload concept.
- Status reporting for an inline-completed core should show core progress as complete even though no core parts were confirmed.
- The same path derivation rules used by the Traiettoria del Viaggio feature apply: points ordered by timestamp, coordinates as longitude/latitude, LineString derived server-side, distance by PostGIS.
- The mobile sync queue keeps one local SyncJob. It changes the core phase from package/presign/upload/complete/poll to build-inline-payload/post-core.
- After successful core inline response, the mobile stores the returned remote ingestion id and remote trip id.
- After successful core inline response, the mobile may set local core status to completed even if raw status remains pending or failed retryably.
- The mobile should continue raw upload in the same processing pass when raw parts exist and the backend raw status can receive them.
- The mobile should retain current retry/backoff behavior for network or server failures.
- The mobile should compute expected raw part counts from the raw package exactly as it does today.
- The mobile should stop creating gzip files for GPS points and state transitions on the new path.
- The mobile may continue creating gzip files for sensor windows.
- The UI map gate should depend on completed core, returned remote trip id, and `map_available=true`, not on raw completion.

## State And Schema Changes

### Backend persistent schema

- Add a backend migration for TripIngestion.
- Add `core_payload_sha256` as a nullable/blank 64-character field. This stores the inline core payload hash and is used to detect same-session/different-payload conflicts.
- Add `core_payload_size_bytes` as a numeric field. This records the decoded inline JSON body size accepted by the backend and supports auditing the 1 MB limit.
- Add `core_ingestion_mode` with values equivalent to `LEGACY_PARTS` and `INLINE`. Existing rows default to `LEGACY_PARTS`; new inline requests set `INLINE`.
- Keep `core_status` and `raw_status` as the phase state machine. Do not add a new backend phase status only for inline core.
- Keep `expected_core_parts` for legacy part-based core. For inline core, no core parts are expected and no core TripIngestionPart rows are created.
- Keep `expected_raw_parts` unchanged. Inline core still declares raw expectations in the request.
- Do not persist `map_available` on TripIngestion. It is derived from the materialized Trip/path and returned in API responses.
- Do not reuse `manifest_sha256` for inline core payload protection. That field remains part of the legacy complete-core manifest path; inline core uses `core_payload_sha256`.

### Backend phase transitions

- New inline happy path: `PENDING -> PROCESSING -> COMPLETED` inside the request, or direct completion within one transaction if no intermediate state is externally visible.
- Inline core does not use `RECEIVING`, `RECEIVED`, or `QUEUED` on the happy path.
- `QUEUED` and `PROCESSING` can still exist for legacy core ingestions already handed to Celery.
- If an inline request finds legacy `QUEUED` or `PROCESSING`, it returns current state and does not start a second materialization.
- Validation errors such as empty core, oversized body, or hash mismatch return 4xx and must not silently produce a completed core.
- Same-session/different-hash returns `409 Conflict` and must not mutate a completed ingestion.
- Final core failure remains `FAILED_FINAL` and is not auto-reopened by inline core.

### Backend API state surface

- Add an inline core response DTO with `ingestion_id`, `trip_id`, `core_status`, `raw_status`, `gps_points`, `state_transitions`, `path_points`, `distance_meters`, and `map_available`.
- Extend the ingestion status response to expose `map_available` and `core_ingestion_mode` so mobile/debug clients do not need to infer them from legacy part state.
- Existing raw presign/confirm/complete-raw responses keep their current shape unless raw upload needs the returned ingestion status for continuity.

### Mobile local schema

- Add a Drift migration for SyncJobs.
- Add `corePayloadSha256` as a nullable text field. This records the inline core hash used by the current SyncJob.
- Add `corePayloadSizeBytes` as an integer field with default 0. This lets the mobile record what it sent and helps diagnose oversized-core cases.
- Add `coreMapAvailable` as a boolean field with default false. This persists the backend `map_available` signal across app restarts.
- Keep `coreStatus` and `rawStatus` as the local SyncJob state machine. Do not add a separate local enum only for inline core.
- Keep `remoteIngestionId` and `remoteTripId`. Inline core fills both from the response.
- Bump the Drift schema version and regenerate the generated database code.

### Mobile local state transitions

- New local core happy path: `PENDING -> PACKAGING -> UPLOADING -> COMPLETED`.
- `PACKAGING` now means building the inline core JSON/hash plus raw package metadata, not writing GPS/state gzip files.
- `UPLOADING` now means posting inline core for the core phase, not presigned PUT for GPS/state files.
- `WAITING_PROCESSING` remains available for legacy core and unusual backend `QUEUED`/`PROCESSING` responses, but should disappear from the inline happy path.
- After successful inline core response, local core becomes `COMPLETED`, `remoteIngestionId` and `remoteTripId` are stored, and `coreMapAvailable` is set from `map_available`.
- Local raw may then move to `PACKAGING`/`UPLOADING`/`COMPLETED` or retryable failure without changing completed core.
- The Home/UI gate for opening the map is `coreStatus=COMPLETED && remoteTripId != null && coreMapAvailable=true`.
- If `coreStatus=COMPLETED` but `coreMapAvailable=false`, the Viaggio is synchronized but the map button should not be shown as available; the UI may show a non-blocking "traiettoria non disponibile" message if needed.

## Testing Decisions

- The highest-value backend seam is the authenticated ingestion API endpoint. Tests should issue `POST /api/ingestion/trips/core` and assert the external response plus persisted domain effects.
- Backend tests should verify successful core completion with GPS and transitions, GPS-only completion, transitions-only completion, empty-core rejection, oversized-body rejection, hash mismatch, same-hash retry idempotency, different-hash conflict, existing completed ingestion, failed-final conflict, and legacy queued/processing behavior.
- Backend tests should assert that successful inline core creates or reuses one TripIngestion for the user/session and one Trip for the session.
- Backend tests should assert the new TripIngestion schema fields: `core_payload_sha256`, `core_payload_size_bytes`, and `core_ingestion_mode`.
- Backend tests should assert that `core_status=COMPLETED` and `raw_status` follows `expected_raw_parts`.
- Backend tests should assert that enough GPS evidence creates a map-ready trajectory and `map_available=true`.
- Backend tests should assert that insufficient GPS evidence still completes core but returns `map_available=false`.
- Backend tests should assert that inline core creates no core TripIngestionPart rows.
- Backend tests should assert that status responses expose `map_available` and `core_ingestion_mode`.
- Backend tests should assert that the trajectory uses the same ordering and longitude/latitude semantics already covered by the trajectory feature.
- Backend tests should assert user isolation: the endpoint must not reuse or expose another user's ingestion for the same or different session id.
- Backend tests should verify that inline core does not require object storage and does not create core part rows.
- Mobile tests should use the existing SyncJob queue seam with a fake ingestion API, following the style of the current sync queue tests.
- Mobile tests should verify that a SyncJob posts inline core first, stores the returned ingestion id and trip id, marks core completed, and then continues raw upload if raw parts exist.
- Mobile tests should verify that the new SyncJob fields persist `corePayloadSha256`, `corePayloadSizeBytes`, and `coreMapAvailable`.
- Mobile tests should verify that the map gate is false when core is completed and trip id exists but `coreMapAvailable=false`.
- Mobile tests should verify that a raw failure after core success leaves core completed and keeps the map gate available.
- Mobile tests should verify that same-session retries call inline core idempotently and do not re-run legacy core presigned upload.
- Mobile tests should verify that the builder produces a deterministic core JSON and hash from the local acquisition database.
- Mobile tests should verify that GPS/state core evidence is no longer written as gzip parts on the new path, while sensor window raw evidence still is.
- Good tests should observe behavior at API, repository, or queue boundaries and avoid asserting private helper call order unless no higher seam can expose the behavior.
- Existing prior art includes backend ingestion endpoint tests, trajectory endpoint tests, mobile trip package builder tests, and mobile sync queue tests.

## Out of Scope

- Removing legacy presigned core endpoints.
- Rewriting Raw Sensor Ingestion.
- Activating final HAR processing.
- Changing raw retention or cleanup behavior.
- Changing sensor window chunk format.
- Changing the Traiettoria del Viaggio endpoint or map rendering beyond consuming faster core completion.
- Offline maps or background map tiles.
- Introducing a second TripIngestion for raw.
- Allowing automatic fallback from oversized inline core to legacy presigned core.
- Building a manual recovery UI for `FAILED_FINAL`.
- Changing authenticated user/session ownership semantics.

## Further Notes

- This PRD depends on the domain language in the project glossary: Viaggio,
  Ingestione del Viaggio, Core Ingestion, Raw Sensor Ingestion, Viaggio
  Sincronizzato, and Traiettoria del Viaggio.
- This PRD is governed by ADR 0001 and ADR 0002.
- The intended implementation order is state/schema migration first, then
  backend inline core API, then mobile SyncJob inline core, then raw continuation
  after inline core, then legacy compatibility and hardening.
- The primary performance win is removing object-storage round trips, Celery
  scheduling, and polling from the small core evidence path.
- The safety win is preserving the existing idempotency model while adding a
  payload hash to detect same-session/different-content bugs.
