# PRD: Eventi SSE di Stato dell'Arricchimento del Diario

> Copia locale per il tracker; la versione di riferimento vive anche in [`docs/prd/sse-diary-status-events.md`](../../docs/prd/sse-diary-status-events.md). Piano operativo file-by-file in [`PIANO_SSE_EVENTI_DIARIO.md`](../../PIANO_SSE_EVENTI_DIARIO.md).

## Problem Statement

Dopo che un Viaggio completa la Core Ingestion, l'app mobile resta in attesa che la fase di Arricchimento del Viaggio (HAR) produca i Segmenti di Mobilita. Per saperlo, ascolta una connessione SSE su `GET /mobility/trips/{id}/events` che oggi emette un solo evento, `event: diary_enriched`, con un payload (`data: {"trip_id": N}`) che il client **ignora completamente**. Non esiste alcuna gestione del fallimento: se la fase HAR fallisce in modo definitivo (`TripIngestion.raw_status = FAILED_FINAL`), l'app non lo scopre mai — resta sullo stato "in attesa" finche' non scatta il timeout dei 300 secondi, ripetendo l'attesa a ogni apertura della pagina senza mai informare l'utente che il diario di quel viaggio non si arrichira'.

## Solution

Ridisegnare il contratto dell'evento SSE perche' sia **guidato dal contenuto** (`data.status`) invece che dal nome dell'evento, e perche' comunichi anche l'esito di fallimento con un messaggio comprensibile, senza esporre dettagli interni del backend.

Flusso aggiornato:

```text
Core completato -> app apre SSE /trips/{id}/events
  -> backend controlla a ogni giro:
       Trip.status == PROCESSED        -> event: diary_status, data.status = "enriched"
       TripIngestion.raw_status ==
         FAILED_FINAL                  -> event: diary_status, data.status = "failed", data.reason = <codice>
       (nessuno dei due)               -> ": waiting" / ": timeout"
  -> app riceve "enriched"  -> richiama GET /diary, mostra il diario arricchito
  -> app riceve "failed"    -> mostra messaggio utente, tracciato resta visibile sulla mappa
```

L'SSE resta un **campanello**, non un trasportatore di dati: l'unico read model canonico del Diario e' sempre `GET /diary`.

## User Stories

1. As a Proprietario del Viaggio, I want to be notified automatically when my Diario finishes enriching, so that I don't have to manually refresh the trip page.
2. As a Proprietario del Viaggio, I want to be told clearly when the Diario enrichment has failed, so that I'm not left waiting indefinitely without explanation.
3. As a Proprietario del Viaggio, I want to still see my recorded track on the map even if the Diario enrichment fails, so that only the activity breakdown is missing, not my whole trip.
4. As a Proprietario del Viaggio, I want a failed enrichment message in Italian that makes sense to me, not a raw technical error, so that the failure is understandable.
5. As a Proprietario del Viaggio, I want re-entering the trip page to give the enrichment a fresh chance to succeed, so that a manual retry by support staff isn't wasted on a stale client state.
6. As a Proprietario del Viaggio, I want a manual refresh on the same page to not repeatedly re-request and re-display the same failure, so that the screen doesn't loop uselessly.
7. As a developer, I want the SSE event's `status` field to use the same domain vocabulary as the rest of the codebase (Arricchimento del Viaggio), so that backend, app, and glossary stay aligned.
8. As a developer, I want the failure reason to be a stable machine-readable code, not raw exception text, so that internal details (paths, queries, table names) are never leaked to the client and so the app owns translation/UX.
9. As a developer, I want the mutual exclusivity between "enriched" and "failed" documented, so that future readers don't assume a check-order priority that doesn't exist.
10. As a developer, I want the SSE timeout to stay safely larger than the worst-case HAR retry duration, so that a terminal failure is never missed in favor of a silent generic timeout.

## Implementation Decisions

- Singolo nome evento `diary_status`; la reazione del client si basa sul campo `data.status`, non sul nome dell'evento.
- Valori di `status`: `enriched` | `failed`. Mai `processing`/`processed` nel contratto pubblico (sono nomi interni dell'enum `Trip.Status`).
- `failed` include un campo `reason` con un **codice stabile** (v1: `diary_enrichment_failed`), mai il testo grezzo dell'eccezione.
- Rilevamento `failed`: `TripIngestion.raw_status == FAILED_FINAL` (terminale). Esplicitamente **non** `FAILED_RETRYABLE` (potrebbe ancora riuscire) e **non** `HarJob.status`/`HarJob.error` (vanno in `FAILURE` anche durante un retry non ancora esaurito — falso amico).
- `enriched` e `failed` sono mutuamente esclusivi per costruzione (stesso `run_pipeline`, o arriva a `PROCESSED` o va in `except` senza mai arrivarci) — l'ordine di controllo nel codice non ha rilevanza semantica.
- Timeout SSE (300s) deve restare maggiore del tempo massimo di retry HAR (~90s con `max_retries=3`, `default_retry_delay=30`); da riverificare se la configurazione di retry Celery cambia.
- Cutover diretto dal vecchio formato (`event: diary_enriched`) al nuovo: nessuna compatibilita' retroattiva, progetto ancora in sviluppo senza utenti reali da proteggere.
- Lato app: nuovo value type `DiaryEvent { status, tripId, reasonCode }` con `enum DiaryEventStatus { enriched, failed, unknown }`; parser tolerante a payload malformati (produce `unknown`, non un'eccezione), stessa filosofia di `_tryDecode` gia' presente nel client.
- Lato app: `enrichmentFailed` (bool) e `enrichmentErrorMessage` (String?) sono campi **dedicati** sullo state del cubit, non riuso del campo `error` esistente (quel campo significa "fallimento totale di pagina, niente mappa" — semantica incompatibile).
- Nessuna mappa codice -> messaggio in questa iterazione: v1 ha un solo codice reale, confronto diretto inline con fallback generico per codici non riconosciuti.
- Regola `load()` vs `reload()`: un nuovo ingresso nella pagina (`load()`) riparte sempre da zero e riapre l'SSE anche dopo un fallimento precedente; un refresh manuale sulla stessa pagina (`reload()`) non riapre l'SSE se il fallimento e' gia' stato osservato in quella sessione, per evitare il loop "richiedi di nuovo -> ricevi di nuovo failed". Il flag di sessione vive come campo privato sul cubit, non nello state immutabile.
- Nessun pulsante "riprova" in questa iterazione (richiederebbe un endpoint di re-trigger della fase HAR, fuori scope).

## Testing Decisions

- Backend (`mobility/tests/test_trip_track.py`): aggiornare l'asserzione dell'evento di successo per includere `"status":"enriched"`; aggiungere un test con `TripIngestion.raw_status = FAILED_FINAL` che verifica l'emissione di `diary_status`/`failed` con `reason: diary_enrichment_failed`.
- Frontend (`trip_track_cubit_test.dart`): `FakeTripTrackService` espone metodi di comodo `emitEnriched(tripId)` / `emitFailed(reasonCode)`; aggiornare il test di successo esistente; aggiungere un test di fallimento che verifica `enrichmentFailed = true`, messaggio presente, e nessuna nuova `GET /diary`; aggiungere un test per la regola `load()` vs `reload()` (un `reload()` dopo un fallimento non richiama di nuovo `watchDiaryEvents`).
- Riusare i fixture/helper di test gia' esistenti per autenticazione, creazione trip e streaming response (`_read_streaming_body`, `auth_headers`, `create_trip`).

## Out of Scope

- Rilevamento di Raw Sensor Ingestion abbandonata (mai completata dal client, nessun `HarJob` mai accodato) — richiederebbe una soglia di age che e' una decisione di prodotto separata.
- Pulsante "riprova" lato app e relativo endpoint di re-trigger della fase HAR.
- Distinzione di piu' codici di fallimento (es. `invalid_sensor_data` per `InvalidRawSensorPayload`) — v1 usa un solo codice generico.
- Migrazione del meccanismo di notifica da polling del DB a Redis Pub/Sub — cambierebbe solo come l'endpoint *scopre* l'esito, non il contratto SSE verso l'app.
- Versionamento del contratto SSE per compatibilita' con client piu' vecchi.

## Further Notes

Decisioni scartate (per memoria):

- **Event-carried state transfer** (intero diario nel `data:` dell'SSE): scartata — payload pesante e fragile (`path_geojson` per segmento), duplicherebbe la serializzazione di `get_diary`, introdurrebbe una seconda fonte di verita'.
- **`data: {}` senza payload**: scartata — chiuderebbe la porta al multiplexing futuro e renderebbe gli eventi non auto-descrittivi nei log.
