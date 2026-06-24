# 01 - Migrare il contratto SSE del diario a un evento guidato dal contenuto (`diary_status` / `enriched`)

Status: ready-for-agent

## Parent

`.scratch/sse-diary-status-events/PRD.md`

## What to build

Sostituire l'evento SSE attuale (`event: diary_enriched`, payload ignorato dal client) con un contratto **guidato dal contenuto**: un solo nome evento, `diary_status`, dove la reazione del client si basa sul campo `data.status`, non sul nome dell'evento.

Cutover diretto, nessuna compatibilita' con il vecchio formato (progetto ancora in sviluppo, nessun utente reale con app vecchia da proteggere).

Cambia end-to-end:

- **Backend** (`mobility/api.py`): il generatore dello stream SSE emette, quando `Trip.status == PROCESSED`:
  ```
  event: diary_status
  data: {"trip_id":42,"status":"enriched"}
  ```
  invece del vecchio `event: diary_enriched`. I commenti di keep-alive (`: waiting`, `: timeout`) restano invariati.
- **Frontend** (`trip_track_service.dart`): il parser SSE oggi ignora completamente le righe `data:` e yielda solo il nome evento come `String`. Va riscritto per accumulare `event:` + `data:` fino alla riga vuota (ignorando i commenti `:`), produrre un nuovo value type `DiaryEvent { status, tripId, reasonCode }` con `enum DiaryEventStatus { enriched, failed, unknown }`, ed esporre `watchDiaryEvents` come `Stream<DiaryEvent>` invece di `Stream<String>`. Un `data:` non parsabile o con `status` non riconosciuto produce `DiaryEvent(status: unknown)`, mai un'eccezione (stessa filosofia tollerante di `_tryDecode`, gia' presente nel file, che non lancia mai su JSON malformato).
  - `unknown` esiste gia' come valore previsto in questa slice anche se nessun produttore reale lo emette ancora: serve a non far sembrare la connessione caduta per un payload imprevisto, ed e' il valore di fallback anche per qualunque `status` futuro non ancora gestito dall'app.
- **Frontend** (`trip_track_cubit.dart`): `_diaryEventSubscription` diventa `StreamSubscription<DiaryEvent>`; la reazione di successo (oggi `if (event != 'diary_enriched') return; _refreshAfterDiaryEvent(...)`) si aggancia a `event.status == DiaryEventStatus.enriched`.

Questa slice e' deliberatamente la **prefattorizzazione** per la 02: prepara il contratto e il parser cosi' che aggiungere la gestione del fallimento sia un'aggiunta pulita, non un secondo refactor del parser.

> Nota terminologica: `status` usa il vocabolario di dominio (**Arricchimento del Viaggio**, vedi `CONTEXT.md`), non l'enum interno `Trip.Status.PROCESSED`. Valore di successo: `enriched`. Mai `processing`/`processed` nel contratto pubblico — sono nomi tecnici interni, non il linguaggio del progetto.

## Acceptance criteria

- [ ] Lo stream SSE emette `event: diary_status` con `data: {"trip_id":N,"status":"enriched"}` quando `Trip.status == PROCESSED`; il vecchio `event: diary_enriched` non viene piu' emesso in nessun caso.
- [ ] `watchDiaryEvents` espone `Stream<DiaryEvent>`; il parser accumula correttamente `event:`/`data:` fino alla riga vuota e ignora i commenti SSE (`: waiting`, `: timeout`).
- [ ] Un payload `data:` malformato o con `status` non riconosciuto produce `DiaryEvent(status: unknown)` senza lanciare eccezioni e senza chiudere lo stream in modo anomalo.
- [ ] Il cubit reagisce a `DiaryEventStatus.enriched` esattamente come reagiva prima a `event == 'diary_enriched'` (richiama `_refreshAfterDiaryEvent`, ricarica il diario).
- [ ] Test backend aggiornato: l'asserzione sull'evento di successo verifica `event: diary_status` e `"status":"enriched"` nel body, non piu' `event: diary_enriched`.
- [ ] Test frontend aggiornato: il test esistente che oggi fa `service.events.add('diary_enriched')` usa il nuovo tipo `DiaryEvent` e continua a verificare che il cubit ricarichi il diario.
- [ ] Nessuna regressione sul comportamento di successo osservabile dall'app: un arricchimento completato continua a far apparire i segmenti nel diario senza intervento dell'utente.

## Blocked by

None - can start immediately
