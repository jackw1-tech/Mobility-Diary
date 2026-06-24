# Piano: Eventi SSE del Diario (successo + fallimento)

**Data:** Giugno 2026
**Ambito:** Notifica all'app mobile dello stato di arricchimento del Diario di un viaggio, via SSE (Server-Sent Events).
**Stato:** Da implementare. Questo documento raccoglie le decisioni prese e il piano operativo.

**Compatibilità di rilascio:** progetto ancora in sviluppo, nessun utente reale con versione app precedente da supportare. **Cutover diretto** dal vecchio formato (`event: diary_enriched`, già a deploy) al nuovo (`event: diary_status`, `data.status`) — nessun invio doppio, nessuna versione transitoria.

---

## 1. Contesto

Quando l'utente chiude un viaggio, il backend lo elabora in **due fasi separate**:

| Fase | Cosa produce | Task Celery | Stato finale del Trip |
|---|---|---|---|
| **1. CORE** | il tracciato (GPS + path sulla mappa) | `process_trip_ingestion` | `Trip.status = CLOSED` |
| **2. DIARIO (HAR)** | i segmenti con le attività (a piedi/bici/auto…) | `process_trip_har_final` → `run_pipeline` | `Trip.status = PROCESSED` |

La fase 2 è lenta (carica le sensor window + modello TensorFlow HAR). L'app, dopo che il **core è completato**, apre una connessione SSE su `GET /mobility/trips/{id}/events` e **resta in ascolto** finché il Diario non è pronto. Quando lo è, il backend emette un evento e l'app **ricarica** `GET /diary` per mostrare i segmenti arricchiti.

> L'SSE è un **campanello**, non trasporta i dati del diario. I dati veri passano sempre dalla `GET /diary` (read model canonico). Vedi §6 per il motivo (scartata l'ipotesi "event-carried state transfer").

### 1.1 Riferimenti nel codice

- Endpoint SSE: [`trip_events`](back-end/ninja/mobility/api.py) — `back-end/ninja/mobility/api.py`
- Generatore stream: `_trip_diary_event_stream`
- Transizione a `PROCESSED`: `back-end/ninja/mobility/ml/pipeline.py:282`
- Fallimento fase HAR: `TripIngestion.raw_status = FAILED_FINAL` + `error_message` — `back-end/ninja/mobility/tasks.py:380-386`
- Client SSE Flutter: `mobile/diary/lib/network/service/trip_track_service.dart` (`watchDiaryEvents`)
- Reazione Flutter: `mobile/diary/lib/state_management/cubits/trip_track_cubit/trip_track_cubit.dart`

---

## 2. Stato attuale (già fatto)

Migrazione WSGI → ASGI per non bloccare i worker durante lo streaming SSE (già a deploy su Railway):

- **Dockerfile** `back-end/ninja/Dockerfile`: avvio con `gunicorn config.asgi:application -k uvicorn.workers.UvicornWorker --workers ${WEB_CONCURRENCY:-2} --bind 0.0.0.0:${PORT:-8000}`.
- **requirements.txt**: aggiunto `uvicorn[standard]>=0.30.0,<1.0`.
- **api.py**: `trip_events`, `_trip_diary_event_stream`, `_is_trip_diary_processed` riscritti `async` (`await asyncio.sleep`, `aexists()`, `aget_object_or_404`).
- **Meccanismo attuale**: polling del DB ogni 2s (`_TRIP_EVENT_POLL_SECONDS = 2`), timeout a 300s. Emette solo `event: diary_enriched` con `data: {"trip_id": N}`.

**Limiti dello stato attuale che questo piano risolve:**
1. L'evento ha un `data` ridondante (`trip_id` che l'app già conosce dall'URL) e che il client **ignora** del tutto (parsa solo le righe `event:`).
2. **Nessuna gestione del fallimento:** se la fase HAR fallisce (`raw_status = FAILED_FINAL`), l'app non lo sa e resta in attesa fino al timeout di 5 minuti.

---

## 3. Cosa implementare

Eventi SSE **guidati dal contenuto** (`data.status`), con esito sia di successo sia di fallimento.

### 3.1 Formato evento (Decisione 1 → **B**: nome evento unico, reazione sul contenuto)

Un solo nome evento, `diary_status`. La reazione del client si basa **sul campo `status` nel `data`**, non sul nome dell'evento.

- **Successo:**
  ```
  event: diary_status
  data: {"trip_id":42,"status":"enriched"}

  ```
- **Fallimento:**
  ```
  event: diary_status
  data: {"trip_id":42,"status":"failed","reason":"diary_enrichment_failed"}

  ```

> Nota terminologica: `status` usa il vocabolario di dominio (**Arricchimento del Viaggio**, vedi `CONTEXT.md`), non l'enum interno `Trip.Status.PROCESSED`. Valori: `enriched` | `failed`. Mai `processing`/`processed` nel contratto pubblico — sono nomi tecnici interni, non il linguaggio del progetto.

> **Copertura del fallimento — fuori scope dichiarato:** l'evento `failed` viene emesso solo quando `TripIngestion.raw_status == FAILED_FINAL` (il task HAR è partito ed ha esaurito tutti i retry). **Non copre** il caso in cui la Raw Sensor Ingestion non viene mai completata dal client (es. app in background, upload mai ripreso) e quindi nessun `HarJob` viene mai accodato: `raw_status` resta in uno stato non-terminale per sempre, e l'SSE termina con il generico `: timeout` invece che con un messaggio di errore. Rilevare le ingestion "abbandonate" richiederebbe una soglia di age che è una decisione di prodotto, non solo tecnica — deliberatamente non affrontata in questa iterazione.
>
> Nota correlata sui tempi: il timeout SSE (300s, `_TRIP_EVENT_MAX_SECONDS`) ha ampio margine sul tempo massimo di retry HAR (~90s con `max_retries=3`, `default_retry_delay=30`), quindi il caso `FAILED_FINAL` viene sempre intercettato entro il timeout. Se in futuro la configurazione di retry di Celery cambia in modo sostanziale, verificare che resti `tempo massimo di retry < timeout SSE`.
- I keep-alive restano commenti SSE ignorati dal client: `: waiting` / `: timeout`.

**Perché B:** è la più fedele al principio "reagisci al contenuto". Il nome evento non porta più semantica di reazione (resta `diary_status` solo per leggibilità nei log). Niente ridondanza nome ↔ status.

### 3.2 `reason` come codice stabile (Decisione 2 → **A**: codice macchina, traduce il front-end)

Il `reason` **non** è il testo grezzo dell'eccezione (`error_message`), ma un **codice stabile** mappato dal backend. Motivi:
- **Sicurezza:** `str(exc)` può contenere dettagli interni (path, query, tabelle) da non esporre al client.
- **UX/i18n:** il messaggio mostrato all'utente lo decide e traduce il front-end.

**Codici v1:**

| `reason` | Significato | Messaggio utente (IT, lato app) |
|---|---|---|
| `diary_enrichment_failed` | fallimento terminale della fase HAR (`raw_status = FAILED_FINAL`) | "Non siamo riusciti a elaborare il diario di questo viaggio." |

> v1 usa un **unico codice generico**. Estensione futura: distinguere casi (es. `invalid_sensor_data` per `InvalidRawSensorPayload`) — richiederebbe di salvare un `failure_code` stabile lato task invece di derivarlo dal testo. Rimandato.

### 3.3 Reazione dell'app (Decisione 3 → **mostra il messaggio**, niente retry)

Alla ricezione di `status: "failed"`:
- smette di mostrare lo stato "in attesa" (`enrichmentPending = false`),
- segna `enrichmentFailed = true` e salva il messaggio utente (derivato dal `reason`),
- la UI **mostra il messaggio**. Il **tracciato resta visibile** sulla mappa: fallisce solo l'arricchimento del diario, non il viaggio.
- **Nessun pulsante "riprova"** in questa iterazione (richiederebbe un endpoint di re-trigger della fase HAR, che non esiste: scope separato).

**Regola di re-tentativo `load()` vs `reload()`** (l'esito di fallimento non è esposto da `GET /diary` — il `DiaryOut` non porta `raw_status` — quindi l'unico modo in cui il cubit lo scopre è l'evento SSE stesso):
- **`load(tripId)`** (ingresso nella pagina del viaggio): riparte sempre da zero, riapre l'SSE anche se in una sessione precedente c'era stato un fallimento — un nuovo ingresso merita un nuovo tentativo onesto (es. l'elaborazione potrebbe essere stata rilanciata manualmente nel frattempo).
- **`reload()`** (refresh manuale mentre l'utente è già sulla pagina, es. pull-to-refresh): se il cubit ha già osservato `enrichmentFailed = true` in questa sessione di pagina, **non riapre l'SSE** — evita il loop "richiedi di nuovo → ricevi di nuovo failed" individuato in fase di design. Il refresh continua comunque a rifare `fetchTrack`/`fetchDiary` per gli altri dati (es. per il caso "errore di rete", non collegato a questa feature).

**Dettaglio tecnico — dove vive il flag "ho già visto il fallimento":** non nello `TripTrackCubitState` immutabile (verrebbe ricostruito da zero a ogni `_load()`, perdendo l'informazione prima di poterla leggere). Vive come **campo privato sul cubit stesso**, stesso pattern già usato per `_tripId` e `_diaryEventSubscription` ([trip_track_cubit.dart:9-10](mobile/diary/lib/state_management/cubits/trip_track_cubit/trip_track_cubit.dart#L9-L10)) — es. `bool _sawEnrichmentFailureThisSession`. `load()` lo resetta a `false`; `reload()` lo legge per decidere se saltare `_watchPendingDiaryIfNeeded`.

---

## 4. Piano operativo

### 4.1 Backend — `back-end/ninja/mobility/api.py`

1. Importare `TripIngestion` dai models.
2. Cambiare il formato dell'evento di successo: nome `diary_status`, `data: {"trip_id":N,"status":"enriched"}`.
3. Aggiungere helper async `_trip_diary_failure(trip_id, user_id) -> str | None`:
   - query `TripIngestion.objects.filter(trip_id=…, user_id=…, raw_status=FAILED_FINAL)` (terminale; **non** `FAILED_RETRYABLE`, che potrebbe ancora riuscire);
   - ritorna il **codice** `"diary_enrichment_failed"` se presente, altrimenti `None`.
   - **Attenzione, falso amico:** non usare `HarJob.status`/`HarJob.error` come segnale di fallimento. In [tasks.py:391-407](back-end/ninja/mobility/tasks.py#L391-L407), `job.status = HarJob.Status.FAILURE` viene impostato **anche quando il task ritenterà** (cioè non è terminale) — solo `TripIngestion.raw_status == FAILED_FINAL` distingue "fallito per sempre" da "fallito questo tentativo, riprova tra 30s".
4. Nel loop di `_trip_diary_event_stream`, a ogni giro:
   - **`enriched`** (`Trip.status == PROCESSED`) e **`failed`** (`TripIngestion.raw_status == FAILED_FINAL`) sono **mutuamente esclusivi** — non un "controlla prima questo, poi quello": entrambi sono scritti dallo stesso `run_pipeline` ([pipeline.py:282](back-end/ninja/mobility/ml/pipeline.py#L282)), che o arriva in fondo senza eccezioni (→ `PROCESSED`) o va nel blocco `except` ([tasks.py:380](back-end/ninja/mobility/tasks.py#L380)) senza mai raggiungere quella riga. Non possono essere veri entrambi per lo stesso viaggio, quindi l'ordine in cui li controlliamo nel codice non ha rilevanza semantica.
   - se nessuno dei due è vero: timeout raggiunto → `: timeout`, termina; altrimenti → `: waiting`, `await asyncio.sleep(2)`.

### 4.2 Front-end — Flutter

1. **`trip_track_service.dart`**
   - cambiare `watchDiaryEvents` da `Stream<String>` a `Stream<DiaryEvent>`;
   - parser SSE che accumula `event:` + `data:` fino alla riga vuota, ignora i commenti `:`;
   - nuovo value type `DiaryEvent { DiaryEventStatus status; int? tripId; String? reasonCode }` con `enum DiaryEventStatus { enriched, failed, unknown }`;
   - la reazione si decide su `data.status` (fallback al nome evento per robustezza);
   - i nomi `enriched`/`failed` sono lo stesso vocabolario usato lato backend per `status` (§3.1/3.2) — niente sincronizzazione automatica tra Dart e Python, solo disciplina a mantenerli paralleli quando uno dei due cambia;
   - **tolleranza ai payload malformati:** stessa filosofia di `_tryDecode` ([trip_track_service.dart:107-114](mobile/diary/lib/network/service/trip_track_service.dart#L107-L114)), che non lancia mai su JSON non valido. Un `data:` non parsabile o con `status` non riconosciuto produce `DiaryEvent(status: unknown)`, **non** un'eccezione — non deve mai sembrare che lo stream/la connessione sia caduta per colpa di un payload imprevisto.
2. **`trip_track_cubit.dart`**
   - `_diaryEventSubscription` diventa `StreamSubscription<DiaryEvent>`;
   - `switch (event.status)`: `enriched` → `_refreshAfterDiaryEvent`; `failed` → nuovo `_handleDiaryFailure(reasonCode)`; `unknown` → ignora.
   - `_handleDiaryFailure`: cancella la subscription, `enrichmentPending = false`, `enrichmentFailed = true`, messaggio derivato dal codice.
   - **Niente mappa codice→messaggio:** v1 ha un solo codice reale (`diary_enrichment_failed`). Confronto diretto inline (`if (reasonCode == 'diary_enrichment_failed') ... else <messaggio generico di fallback>`), non una struttura `Map`/`switch` pensata per N codici che oggi non esistono. Si introduce la mappa quando arriva un secondo codice reale, non prima — anche nel caso di codice sconosciuto (es. backend più nuovo dell'app) serve comunque un fallback generico.
3. **`trip_track_cubit_state.dart`**
   - aggiungere `final bool enrichmentFailed` (default `false`) e **campo dedicato** `final String? enrichmentErrorMessage` — **non** riuso di `error`. `error` oggi è letto solo dentro `case TripTrackStatus.error` ([trip_diary_tabs.dart:89-90](mobile/diary/lib/ui/pages/trip_diary_tabs.dart#L89-L90), [trip_map_page.dart:26-28](mobile/diary/lib/ui/pages/trip_map_page.dart#L26-L28)) e significa "fallimento totale di pagina, niente mappa" — un significato diverso e incompatibile con "solo il diario non si è arricchito, mappa visibile" (Decisione 3). Riusarlo creerebbe un campo a doppio significato.
4. **UI** (`trip_map_page.dart`): stesso pattern già usato per `enrichmentPending` → `_EnrichmentPendingBanner` ([trip_map_page.dart:237](mobile/diary/lib/ui/pages/trip_map_page.dart#L237)); aggiungere `enrichmentFailed` → nuovo widget `_EnrichmentFailedBanner` nello stesso punto, che mostra `enrichmentErrorMessage`. Il tracciato resta sempre visibile sotto (status rimane `loaded`).

### 4.3 Test

**Backend** (`mobility/tests/test_trip_track.py`):
- aggiornare lo unit test dello stream: il `data` di successo ora include `"status":"enriched"`;
- aggiungere test: con ingestion `raw_status = FAILED_FINAL`, lo stream emette `diary_status`/`failed` + `reason: diary_enrichment_failed`.

**Front-end** (`test/state_management/cubits/trip_track_cubit_test.dart`):
- `FakeTripTrackService.events` passa da `StreamController<String>` a `StreamController<DiaryEvent>` — **rottura di tipo** che richiede di toccare tutti i test esistenti che lo usano, non solo quello del successo (oggi: `service.events.add('diary_enriched')`);
- il fake esponde metodi di comodo `emitEnriched(tripId)` / `emitFailed(reasonCode)` che costruiscono il `DiaryEvent` internamente (stesso spirito ergonomico dei campi già esistenti come `diaryResults`, `trackCalls`) — i test non costruiscono `DiaryEvent(...)` a mano;
- aggiornare il test esistente (usa `service.emitEnriched(tripId)`);
- aggiungere test fallimento: `service.emitFailed(reasonCode)`, verifica `enrichmentFailed = true`, messaggio presente, e che **non** venga rifatta la `GET /diary`;
- aggiungere test per la regola `load()` vs `reload()` (§3.3): dopo un fallimento, `reload()` non richiama `watchDiaryEvents` una seconda volta (`eventStreamCalls` non incrementa); un nuovo `load()` invece sì.

---

## 5. Evoluzione futura (NON in questo piano)

Sostituire il **polling del DB** con **Redis Pub/Sub** (Redis è già il broker Celery):
- in `process_trip_har_final`, dopo il save dello stato, `transaction.on_commit(lambda: redis.publish(f"trip:{id}", …))` (pubblicare **dopo** il commit, per non annunciare dati non ancora leggibili);
- nel generatore SSE: `subscribe` al canale → check DB una volta (caso "già pronto/fallito") → `await get_message()` (attesa event-driven, latenza ~0ms) + timeout di sicurezza.
- Cambia **solo** come l'endpoint *scopre* l'esito; il contratto SSE verso l'app (§3) resta identico.

---

## 6. Decisioni scartate (per memoria)

- **Event-carried state transfer** (mettere l'intero diario nel `data:` per saltare la `GET /diary`): scartata. Il diario contiene i `path_geojson` di ogni segmento (payload pesante, fragile su SSE/proxy), duplicherebbe la serializzazione di `get_diary` e introdurrebbe una seconda fonte di verità. Il round-trip risparmiato è economico e una-tantum per viaggio.
- **`data: {}` / nessun payload**: scartata. Chiuderebbe la porta al multiplexing futuro (una sola connessione per tutti i trip) e renderebbe gli eventi non auto-descrittivi nei log, a parità di costo.
