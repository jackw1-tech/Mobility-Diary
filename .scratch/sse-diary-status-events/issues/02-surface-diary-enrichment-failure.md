# 02 - Rilevare e mostrare il fallimento dell'arricchimento del diario, end-to-end

Status: ready-for-agent

## Parent

`.scratch/sse-diary-status-events/PRD.md`

## What to build

Oggi, se la fase HAR fallisce in modo definitivo, l'app non lo scopre mai: resta sullo stato "in attesa" finche' non scatta il timeout SSE di 300 secondi, ripetendo l'attesa a ogni apertura della pagina senza mai informare l'utente. Questa slice chiude quel buco end-to-end: rilevamento lato backend, propagazione via SSE, reazione e UI lato app.

**Backend** (`mobility/api.py`): aggiungere un helper async che rileva il fallimento terminale e lo emette nello stream:

- Query: `TripIngestion.objects.filter(trip_id=…, user_id=…, raw_status=FAILED_FINAL)` → ritorna il codice `"diary_enrichment_failed"` se presente, altrimenti `None`.
- **Non** usare `FAILED_RETRYABLE` (potrebbe ancora riuscire al prossimo tentativo) e **non** usare `HarJob.status`/`HarJob.error` come segnale: vanno in `FAILURE` anche durante un retry non ancora esaurito, quindi non sono un segnale terminale — useresti un falso amico.
- `enriched` (`Trip.status == PROCESSED`) e `failed` (`raw_status == FAILED_FINAL`) sono mutuamente esclusivi per costruzione (stesso codice di pipeline: o arriva a `PROCESSED` senza eccezioni, o va in un blocco `except` senza mai arrivarci) — non serve un ordine di priorita' tra i due controlli nel loop dello stream.
- Quando rilevato, lo stream emette:
  ```
  event: diary_status
  data: {"trip_id":42,"status":"failed","reason":"diary_enrichment_failed"}
  ```
  Il `reason` e' sempre un **codice stabile**, mai il testo grezzo dell'eccezione (rischio di leak di dettagli interni: path, query, nomi tabelle).
- Vincolo temporale da preservare: il timeout SSE (300s) deve restare maggiore del tempo massimo di retry HAR (oggi ~90s con `max_retries=3`, `default_retry_delay=30`), altrimenti un fallimento finale rischia di non essere mai intercettato prima del timeout generico.

**Frontend** (`trip_track_cubit.dart`): reagire a `DiaryEventStatus.failed` (valore introdotto nella slice 01) con un nuovo `_handleDiaryFailure(reasonCode)`:

- Cancella la subscription SSE, imposta `enrichmentPending = false`, `enrichmentFailed = true`, e il messaggio utente derivato dal codice.
- Niente mappa codice→messaggio: v1 ha un solo codice reale (`diary_enrichment_failed`). Confronto diretto inline con un messaggio di fallback generico per codici non riconosciuti — non costruire una struttura pensata per N codici che oggi non esistono.
- Regola `load()` vs `reload()`: un nuovo ingresso nella pagina (`load(tripId)`) riparte sempre da zero e riapre l'SSE anche se in una sessione precedente c'era stato un fallimento. Un refresh manuale sulla stessa pagina (`reload()`) **non** riapre l'SSE se il cubit ha gia' osservato `enrichmentFailed = true` in questa sessione di pagina — altrimenti si crea un loop "richiedi di nuovo → ricevi di nuovo failed" senza alcun beneficio. Il flag "ho gia' visto il fallimento" vive come campo privato sul cubit (stesso pattern di `_tripId`/`_diaryEventSubscription`), non nello state immutabile, perche' altrimenti verrebbe perso a ogni `_load()`.

**Frontend** (`trip_track_cubit_state.dart`): aggiungere campi **dedicati** `enrichmentFailed` (bool) e `enrichmentErrorMessage` (String?) — non riusare il campo `error` esistente. `error` oggi significa "fallimento totale di pagina, niente mappa" (e' letto solo dentro `case TripTrackStatus.error`); il fallimento dell'arricchimento ha una semantica diversa e incompatibile: solo il diario non si e' arricchito, il tracciato resta visibile.

**Frontend** (`trip_map_page.dart`): stesso pattern gia' usato per `enrichmentPending` → `_EnrichmentPendingBanner`; aggiungere un nuovo widget `_EnrichmentFailedBanner` nello stesso punto, che mostra `enrichmentErrorMessage`. Il tracciato resta sempre visibile sotto (lo `status` generale rimane `loaded`). Nessun pulsante "riprova" in questa iterazione.

## Acceptance criteria

- [ ] Con un `TripIngestion.raw_status == FAILED_FINAL`, lo stream SSE emette `event: diary_status`, `data: {"trip_id":N,"status":"failed","reason":"diary_enrichment_failed"}` invece di continuare ad aspettare fino al timeout generico.
- [ ] Con `raw_status == FAILED_RETRYABLE`, lo stream **non** emette `failed` — continua ad aspettare normalmente (`: waiting`), perche' il task potrebbe ancora riuscire.
- [ ] Il rilevamento del fallimento non si basa in nessun punto su `HarJob.status`/`HarJob.error`.
- [ ] Il cubit, alla ricezione di `failed`, imposta `enrichmentFailed = true`, `enrichmentPending = false`, e un messaggio utente leggibile in `enrichmentErrorMessage` (mai derivato da `error`).
- [ ] La UI mostra il messaggio di fallimento mantenendo il tracciato e la mappa visibili (nessuna transizione allo stato `TripTrackStatus.error` di pagina).
- [ ] Dopo aver visto un fallimento, `reload()` (refresh manuale sulla stessa pagina) **non** riapre una nuova connessione SSE; un nuovo `load(tripId)` (es. rientrando nella pagina) la riapre normalmente.
- [ ] Test backend: nuovo test con `raw_status = FAILED_FINAL` che verifica l'emissione di `diary_status`/`failed` con `reason: diary_enrichment_failed`.
- [ ] Test frontend: nuovo test di fallimento che verifica `enrichmentFailed = true`, messaggio presente, e che **non** venga rifatta la `GET /diary` dopo un fallimento.
- [ ] Test frontend: nuovo test che verifica che `reload()` dopo un fallimento non richiami di nuovo `watchDiaryEvents`, mentre un nuovo `load()` lo fa.

## Blocked by

- `.scratch/sse-diary-status-events/issues/01-content-driven-diary-status-event.md` (richiede il contratto `DiaryEvent`/`diary_status` gia' in piedi)
