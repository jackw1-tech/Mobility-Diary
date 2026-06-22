# PRD - HAR finale asincrono via Celery

> Versione 1 - 2026-06-22.
> Riguarda la fase finale della Raw Sensor Ingestion: lettura dei raw dal bucket,
> inferenza HAR nel worker Celery, e produzione del Diario della Mobilita.
> Rispetta ADR 0003-0012.

## Problem Statement

Il sistema sa gia sincronizzare il Core del Viaggio e caricare le finestre
sensoriali raw nel bucket tramite presigned upload, ma la fase finale e ancora
congelata: `complete-raw` conferma solo che i blob sono arrivati e
`process_trip_har_final` non elabora davvero i dati.

Dal punto di vista dell'utente, questo lascia incompleto il valore centrale del
progetto: il Viaggio puo comparire sulla mappa, ma non diventa ancora un Diario
della Mobilita arricchito con modalita di spostamento, soste leggibili, luoghi
significativi e statistiche basate su Etichette di Attivita.

Dal punto di vista del progetto universitario, manca il ponte dimostrabile tra
dati sensoriali, modello HAR avanzato CNN+GRU, segmentazione del percorso e
diario leggibile privacy-aware. Senza questo ponte, Redis e Celery restano
infrastruttura predisposta ma non parte del valore finale.

## Solution

Quando il mobile completa il caricamento delle sensor window, il backend deve
trattare la Raw Sensor Ingestion come una pipeline asincrona di Arricchimento
del Viaggio:

1. `complete-raw` verifica che tutte le parti raw attese siano confermate nel
   bucket.
2. La fase raw passa da `RECEIVED` a `QUEUED` e accoda un task Celery dopo il
   commit della transazione.
3. Il worker Celery porta la fase raw a `PROCESSING`, scarica i blob
   `sensor_windows`, li decomprime e valida le finestre.
4. Il worker usa un adapter HAR Keras che carica lazy la pipeline CNN 1D + GRU,
   proietta le finestre 500x9 ai primi sei canali, e produce Etichette di
   Attivita con eventuale confidenza.
5. La pipeline del Diario della Mobilita usa GPS, StateTransition e label HAR
   per rigenerare `MobilitySegment` e `SignificantPlace`.
6. Il worker salva un riepilogo leggero in `HarJob.result`, marca
   `raw_status=COMPLETED`, e lascia i raw nel bucket per questa fase del
   progetto.

La semantica degli stati diventa esplicita:

- `raw_status=RECEIVED`: tutte le parti raw sono nel bucket.
- `raw_status=QUEUED`: il task HAR finale e stato accodato.
- `raw_status=PROCESSING`: Celery sta elaborando i raw.
- `raw_status=COMPLETED`: il Diario della Mobilita e stato arricchito.
- `raw_status=FAILED_RETRYABLE`: errore temporaneo, raw conservati e retry
  possibile.
- `raw_status=FAILED_FINAL`: errore definitivo, raw conservati per diagnosi.

Il frontend scopre il completamento dell'Arricchimento del Viaggio con polling
controllato sugli endpoint di stato/read model. Quando `raw_status=COMPLETED`,
il client ricarica un Diario della Mobilita segmentato, non solo la Traiettoria
del Viaggio grezza. Il backend deve quindi esporre una rappresentazione adatta
alla UI, con Segmenti di Mobilita e geometrie/luoghi associati, cosi la mappa
puo passare dalla traccia unica ai segmenti prodotti dall'HAR.

La fusione tra FSM, GPS e HAR usa il tempo come righello comune. Le
`StateTransition` sono eventi puntuali che definiscono macro-intervalli
`STOP`/`MOVE`; le finestre HAR sono intervalli brevi che assegnano Etichette di
Attivita dentro i `MOVE`; i `GpsPoint` sono campioni puntuali usati per derivare
geometria e distanza dei segmenti. Il risultato persistito e il
`MobilitySegment`: una riga Postgres del diario che puo contenere anche un
campo geografico PostGIS `path` per i movimenti. Gli stop usano invece
`SignificantPlace` con centro/raggio/dwell, non una LineString.

## User Stories

1. As a mobile user, I want my uploaded sensor data to become readable diary segments, so that the app tells me what I did rather than only storing raw measurements.
2. As a mobile user, I want the diary to show walking, running, biking, moving vehicle, and idle labels, so that I can understand my mobility patterns.
3. As a mobile user, I want short sensor windows to be aggregated into human-readable time intervals, so that the diary is not a noisy list of five-second predictions.
4. As a mobile user, I want a synchronized Viaggio to remain visible while HAR is processing, so that enrichment does not block the core diary value.
5. As a mobile user, I want the app to keep polling backend processing after raw upload, so that I know when the enriched diary is ready.
6. As a mobile user, I want temporary backend failures not to require another phone upload, so that flaky infrastructure does not waste battery or data.
7. As a mobile user, I want the final diary to distinguish movements and stops, so that stays and travel are understandable.
8. As a mobile user, I want significant dwell intervals to become Luoghi Significativi, so that the diary can say where I stayed without exposing every coordinate.
9. As a mobile user, I want movement segments to carry a prevalent Etichetta di Attivita, so that statistics by mode are meaningful.
10. As a mobile user, I want isolated noisy HAR labels to be smoothed, so that a single bad prediction does not fragment my diary.
11. As a mobile user, I want a slow car in traffic or temporary stop to remain understandable, so that idle-like windows during vehicle movement do not produce misleading segments.
12. As a mobile user, I want backend processing failure to be visible as retryable or final, so that the app can explain whether it is still working or stuck.
13. As a project evaluator, I want the system to demonstrate a real HAR model, so that the advanced HAR requirement is satisfied by more than GPS speed rules.
14. As a project evaluator, I want the model's input format and class mapping to be documented, so that the relation can explain the technical choices.
15. As a project evaluator, I want the final output to match diary examples such as "08:15-08:35 bike movement", so that the implementation answers the assignment.
16. As a backend operator, I want inference outside HTTP requests, so that web workers are not blocked by TensorFlow and model execution.
17. As a backend operator, I want Celery to retry transient HAR failures, so that object storage or worker hiccups are recoverable.
18. As a backend operator, I want raw sensor evidence preserved after failures, so that diagnosis and reprocessing remain possible.
19. As a backend operator, I want raw sensor evidence preserved after success for now, so that model comparison, metrics, and report writing remain possible.
20. As a backend operator, I want `raw_status=COMPLETED` to mean diary enrichment completed, so that status reflects product value rather than byte transfer.
21. As a backend operator, I want `raw_status=RECEIVED` to mean uploaded evidence is available, so that upload and processing are separate states.
22. As a backend operator, I want HAR processing to be idempotent, so that duplicate Celery delivery does not duplicate segments.
23. As a backend operator, I want the worker to regenerate derived diary entries, so that reprocessing with an updated model is deterministic.
24. As a backend operator, I want TensorFlow loaded lazily and cached in the worker, so that startup and repeated tasks remain manageable.
25. As a backend operator, I want the Keras adapter to accept the existing 500x9 upload contract, so that the mobile raw format does not need to change.
26. As a backend operator, I want the adapter to use only the first six channels for the current model, so that accelerometer and gyroscope match the trained CNN+GRU.
27. As a backend operator, I want `DRIVING` mapped to `MOVING_VEHICLE`, so that model labels stay inside the existing ActivityLabel vocabulary.
28. As a developer, I want the HAR pipeline to consume in-memory raw windows, so that Postgres does not become a store for bulky sensor matrices.
29. As a developer, I want only final diary data and lightweight run metadata in Postgres, so that the model stays aligned with privacy and storage goals.
30. As a developer, I want `HarJob.result` to contain a summary, so that debugging and report evidence exist without a per-window prediction table.
31. As a developer, I want tests to fake the model adapter, so that backend behavior can be verified without slow TensorFlow execution in normal tests.
32. As a developer, I want tests to fake object storage reads, so that raw parsing and status transitions can be exercised deterministically.
33. As a developer, I want the mobile sync queue to treat `RECEIVED` as not done, so that it does not delete/close the job before HAR finishes.
34. As a developer, I want mobile temp upload files to be cleanable after the backend has accepted raw evidence, so that the phone is not the only copy once the bucket has the blobs.
35. As a developer, I want local sync state to remain open until `raw_status=COMPLETED`, so that the UI can represent backend analysis accurately.
36. As a product stakeholder, I want this work to unlock privacy-aware diary views later, so that detailed raw evidence can remain separate from shareable diary output.
37. As a mobile user, I want the app to refresh when HAR processing finishes, so that I can see the enriched diary without manually guessing when to reopen it.
38. As a mobile user, I want the map to show colored movement segments after enrichment, so that the route communicates activity changes instead of one undifferentiated line.
39. As a mobile user, I want stops to appear as places or stop intervals on the map, so that the diary makes stays as visible as movements.
40. As a frontend developer, I want a segmented diary read model from the backend, so that the client does not reimplement timestamp slicing and segment geometry derivation.
41. As a frontend developer, I want polling to be bounded and resumable, so that app reopen, foreground refresh, and network loss all converge to the latest diary state.
42. As a backend developer, I want the segmented map response to be derived from persisted diary data, so that the frontend sees the same Segmenti di Mobilita used by the diary and statistics.
43. As a backend developer, I want StateTransition, HAR windows, and GPS points fused by time, so that each evidence source has a clear responsibility in the diary.
44. As a backend developer, I want movement Segmenti di Mobilita to persist a PostGIS path, so that the segmented map read model is fast and does not recalculate geometry on every request.
45. As a backend developer, I want stop Segmenti di Mobilita to reference Luoghi Significativi rather than store fake movement geometry, so that stops are represented as places and dwell intervals.
46. As a frontend developer, I want segment geometry produced by the backend, so that the client only renders colored segments and does not need to understand GPS/HAR/FSM fusion rules.

## Implementation Decisions

- `complete-raw` becomes the event boundary that starts final HAR processing.
- `complete-raw` must only enqueue after all declared raw parts are confirmed.
- `complete-raw` should transition the raw phase to `QUEUED` and enqueue Celery with `transaction.on_commit`.
- If raw processing is already `QUEUED`, `PROCESSING`, `COMPLETED`, or retryable, repeated `complete-raw` calls are idempotent and must not enqueue duplicate harmful work.
- `raw_status=RECEIVED` means raw sensor evidence is present in object storage, not that the diary is enriched.
- `raw_status=COMPLETED` means HAR has processed the raw sensor evidence and persisted the enriched Diario della Mobilita.
- The final HAR task runs in Celery, not in the Django request path.
- TensorFlow/Keras dependencies belong to the worker runtime. The Django API should stay focused on upload coordination and status transitions.
- The worker uses a Keras model adapter with lazy loading and process-level caching for the CNN extractor and GRU model.
- The current model contract is CNN 1D feature extraction followed by GRU temporal prediction over sequences of 32 windows.
- The mobile continues uploading raw sensor windows in the existing 500x9 shape.
- The HAR adapter validates each window has 500 samples and at least six channels.
- The HAR adapter passes only accelerometer and gyroscope channels to the model.
- The HAR adapter maps the model class `DRIVING` to the diary label `MOVING_VEHICLE`.
- The adapter should return lightweight prediction objects containing at least time interval, label, and optional confidence.
- The old z-score preprocessing path is not the final model path for the CNN+GRU model, because the new 6-channel model uses its own internal normalization behavior.
- Raw sensor matrices are not persisted in Postgres as `SensorWindow.matrix`.
- Celery reads confirmed raw blob parts from object storage, decompresses JSON gzip, validates the windows, and builds in-memory windows for the pipeline.
- Confirmed raw parts are processed in sequence order so prediction order matches the mobile package order.
- JSON blob validation must reject invalid gzip, invalid JSON, missing `windows`, missing `samples`/`matrix`, inconsistent `sample_count`, invalid timestamp fields, non-positive sample rate, and invalid matrix shape.
- The pipeline should expose an input boundary for in-memory raw windows rather than relying on persisted `trip.sensor_windows`.
- `MobilitySegment` and `SignificantPlace` are the product-facing diary data.
- Per-window predictions are not a primary query model in this PRD.
- `HarJob.result` stores run metadata such as classifier name, model version or artifact names, window count, label distribution, segment count, significant place count, and confidence aggregates when available.
- `HarJob.error` and `TripIngestion.error_message` should capture useful failure messages without dumping raw sensor payloads.
- Final HAR enrichment regenerates derived diary entries for the Viaggio.
- Regeneration deletes existing derived `MobilitySegment` and `SignificantPlace` rows for the Trip and recreates them from the current core evidence, raw evidence, and model output.
- The raw blobs remain in object storage after success for this project phase.
- The raw blobs remain in object storage after failure.
- `HAR_CLEANUP_ENABLED` remains disabled for this PRD.
- A future cleanup policy can be added later, but it is not part of this implementation.
- The worker should use Celery retry semantics for transient failures.
- While retries remain, failures set or expose `raw_status=FAILED_RETRYABLE`.
- After retries are exhausted, failures set `raw_status=FAILED_FINAL`.
- Failure paths never delete raw objects.
- The diary segmentation strategy uses a two-level structure: GPS/FSM state transitions define macro stop/move spans, and HAR labels split movement spans into meaningful activity intervals.
- The temporal fusion rule is: StateTransition decides STOP/MOVE macro-spans, HAR decides activity labels inside MOVE spans, GPS decides geometry and distance, and MobilitySegment stores the derived diary result.
- Stop spans remain `IDLE` in the diary even if the model produces noisy non-idle labels inside them.
- Movement spans are split when label changes are meaningful after smoothing/merging.
- Isolated very short label changes should be smoothed or merged so that the diary remains readable.
- Significant places continue to be inferred from dwell time over a threshold and associated with stop segments.
- Movement Segmenti di Mobilita should persist their derived PostGIS LineString path so the frontend can render a segmented map without slicing raw GPS points.
- Stop Segmenti di Mobilita should not invent a LineString; they should use associated Luoghi Significativi with center, radius, and dwell duration.
- Segment timestamps do not need to match GPS point timestamps or HAR window boundaries exactly. They are derived intervals, and GPS/HAR evidence is selected by temporal overlap with those intervals.
- All fusion should run backend-side in UTC. The frontend receives already-derived segments and should not reconcile timezone, GPS samples, state transitions, and HAR windows itself.
- The Trip should be marked processed only after the enriched diary has been successfully written.
- The mobile client must stop treating `rawStatus == RECEIVED` as complete.
- The mobile client should treat only `rawStatus == COMPLETED` as fully done.
- The mobile client should poll or retry while raw is `QUEUED`, `PROCESSING`, or `FAILED_RETRYABLE`.
- The mobile client may clean temporary upload package files once all raw parts have been accepted by the backend, but it should not mark the SyncJob fully complete until the backend reports `raw_status=COMPLETED`.
- The existing inline Core Ingestion and raw presigned upload contracts remain in place.
- No new public API is required for upload. The status API must expose the updated raw semantics clearly enough for mobile polling.
- The first frontend discovery mechanism is polling, not push notifications, Server-Sent Events, or WebSockets.
- Polling should use the existing ingestion status when the mobile knows the ingestion id, and a diary/read-model endpoint when the UI only knows the trip id.
- When polling observes `raw_status=COMPLETED`, the client should refetch the diary/map read model and render Segmenti di Mobilita instead of only the raw Traiettoria del Viaggio.
- The backend should expose a segmented diary map read model, either by extending the existing diary endpoint or by adding a focused endpoint for map rendering.
- The segmented map read model should include movement segments with activity labels and geometry, and stop segments with associated Luoghi Significativi when available.
- Segment geometry should be derived backend-side from GPS points and segment time intervals; the frontend should not slice the raw track by timestamp.
- Events or push notifications may be added later as a wake-up mechanism, but they must remain hints to refetch the read model, not the source of diary truth.
- A periodic recovery task may be added later to scan for stuck `RECEIVED` or `QUEUED` ingestions, but the primary flow is event-driven from `complete-raw`.

## Testing Decisions

- The primary test seam is the authenticated ingestion API plus Celery task boundary around `complete-raw`.
- Tests should assert external behavior: response status, phase transitions, enqueued/processed job effects, persisted diary rows, and status polling behavior.
- Backend tests should fake object storage reads so the worker receives deterministic gzipped JSON sensor windows.
- Backend tests should fake or monkeypatch the HAR model adapter so normal test runs do not load TensorFlow.
- Backend tests should cover `complete-raw` transitioning from uploaded raw evidence to queued processing.
- Backend tests should cover Celery processing success: `raw_status=COMPLETED`, `HarJob=SUCCESS`, Trip processed, segments regenerated, significant places written when dwell criteria match, and no raw deletion.
- Backend tests should cover retryable failures: storage read failure, temporary model exception, `raw_status=FAILED_RETRYABLE`, error captured, raw preserved.
- Backend tests should cover final failures after retries: invalid JSON, invalid matrix shape, missing model artifacts after retries, `raw_status=FAILED_FINAL`, error captured, raw preserved.
- Backend tests should cover idempotency: running the final HAR task twice does not duplicate `MobilitySegment` or `SignificantPlace` rows.
- Backend tests should cover reprocessing: existing segments/places are replaced by the latest derived diary representation.
- Backend tests should cover model-label mapping from `DRIVING` to `MOVING_VEHICLE`.
- Backend tests should cover that raw matrices are not persisted into the diary database as primary data.
- Backend tests should cover `HarJob.result` summary shape without asserting TensorFlow internals.
- Backend tests should cover status API semantics: `RECEIVED` is not completed, `QUEUED`/`PROCESSING` mean backend analysis, and `COMPLETED` means diary enrichment done.
- Mobile tests should use the existing SyncJob queue seam with a fake ingestion API.
- Mobile tests should cover that `rawStatus=RECEIVED` is no longer considered done.
- Mobile tests should cover that after `completeRawIngestion`, the SyncJob waits/polls until `rawStatus=COMPLETED`.
- Mobile tests should cover raw failure after core success without regressing `remoteTripId` or map availability.
- Mobile tests should cover cleanup behavior for temporary package files separately from final SyncJob completion.
- Backend tests should cover the segmented diary map read model after HAR success, including movement geometries, activity labels, stop/place data, and empty/not-yet-enriched states.
- Backend tests should cover temporal fusion across mismatched timestamps: state transitions at one cadence, GPS points at another, HAR windows at another, and derived Segmenti di Mobilita with stable intervals.
- Backend tests should assert movement Segmenti di Mobilita persist PostGIS LineString geometry derived from GPS points inside each segment interval.
- Backend tests should assert stop Segmenti di Mobilita reference Luoghi Significativi and do not require movement geometry.
- Mobile tests should cover polling from raw processing to completion and refetching the segmented diary map when completion is observed.
- Mobile UI tests should cover the transition from a plain track/loading analysis state to a segmented map state.
- Prior backend test art includes ingestion API tests, ingestion state model tests, and inline core tests.
- Prior mobile test art includes trip package builder tests and trip sync queue tests.
- Model adapter tests should stay narrow: validate shape handling, class mapping, padding to GRU sequence length, and summary output using small fakes where possible.
- Avoid tests that assert private helper call order, exact TensorFlow layer names, or implementation details of boto3 clients unless those are the public boundary being protected.

## Out of Scope

- Building the privacy-aware shared diary view.
- Building dashboard charts or web frontend filtering.
- Computing formal privacy perturbation and quality-of-service metrics.
- Training a new HAR model.
- Evaluating accuracy, precision, recall, or confusion matrix inside the app runtime.
- Adding a per-window prediction table.
- Changing the mobile raw sensor upload format from 500x9 to 500x6.
- Deleting raw blobs after success.
- Adding bucket lifecycle rules.
- Removing legacy core ingestion endpoints.
- Changing Core Ingestion inline behavior.
- Implementing route assistant behavior.
- Adding clustering for recurring significant places beyond the current dwell-based logic.
- Creating a separate inference microservice.
- Making TensorFlow run inside web request handlers.

## Further Notes

- This PRD depends on the domain glossary terms: Viaggio, Ingestione del
  Viaggio, Raw Sensor Ingestion, Evidenza Sensoriale Grezza, Arricchimento del
  Viaggio, Diario della Mobilita, Segmento di Mobilita, Luogo Significativo,
  Etichetta di Attivita, Vista Privacy-Aware, Viaggio Sincronizzato, and
  Traiettoria del Viaggio.
- The current code already has a placeholder `process_trip_har_final` and a
  diary pipeline, but the pipeline currently reads persisted sensor windows.
  This PRD changes that boundary so the worker consumes raw bucket windows in
  memory.
- The current mobile API helper treats `RECEIVED` as raw done. That must change
  because `RECEIVED` now means "uploaded evidence available", not "diary
  enriched".
- The frontend discovery strategy is intentionally polling-first. SSE,
  WebSockets, and push notifications can improve freshness later, but the
  reliable contract is still "poll status, then refetch the segmented diary read
  model".
- The temporal fusion model is deliberately backend-owned: FSM transitions,
  GPS samples, and HAR windows can have different timestamps/cadences, but they
  are reconciled into Segmenti di Mobilita by time overlap before the frontend
  sees them.
- The existing `HarJob` model is sufficient for lightweight run metadata unless
  implementation discovers a strong need for an ingestion-specific foreign key.
- The assignment still requires report-level evaluation of HAR performance. That
  evaluation can use the retained raw evidence and model artifacts, but it is not
  part of this runtime PRD.
