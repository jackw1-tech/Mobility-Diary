# PRD: Sostituzione del Polling SSE con Redis Pub/Sub

## Problem Statement

L'endpoint `GET /mobility/trips/{id}/events` notifica oggi l'app via SSE facendo **polling sul database** ogni 2 secondi (`_TRIP_EVENT_POLL_SECONDS`), per un massimo di 300 secondi (`_TRIP_EVENT_MAX_SECONDS`). Ogni connessione SSE aperta genera una query al DB ogni 2 secondi per tutta la durata dell'attesa (fino a 150 query per connessione nel caso peggiore). Con N utenti che aspettano contemporaneamente l'arricchimento del proprio diario, il carico sul DB scala linearmente con N, anche se in pratica la maggior parte delle query non trova nulla di nuovo.

L'infrastruttura per evitare questo carico è già presente e inutilizzata a questo scopo: `REDIS_URL`/`CELERY_BROKER_URL` sono già configurati e puntano alla stessa istanza Redis usata da Celery come broker, e il pacchetto `redis` (con supporto asyncio) è già una dipendenza del progetto.

## Solution

Sostituire il polling con **Redis Pub/Sub**: il task Celery che scrive lo stato terminale del Viaggio (Arricchimento riuscito o fallito in modo definitivo) pubblica un messaggio su un canale dedicato a quel Viaggio; l'endpoint SSE si sottoscrive a quel canale invece di interrogare il DB ogni 2 secondi.

Il contratto SSE verso il client **non cambia** (evento `diary_status`, `data.status` = `enriched`/`failed`/`reason`, definito in `PIANO_SSE_EVENTI_DIARIO.md`): questo lavoro cambia solo **come il backend scopre** che lo stato è cambiato, non cosa manda al client. `GET /diary` resta l'unica fonte di verità per il contenuto del diario; l'SSE resta un campanello.

Flusso aggiornato:

```text
Task Celery scrive stato terminale (commit transazione)
  -> transaction.on_commit: PUBLISH diary_status:{trip_id} {payload}

Endpoint SSE:
  -> SUBSCRIBE diary_status:{trip_id}          (prima di tutto)
  -> controlla stato attuale sul DB una volta
       gia' risolto -> emetti subito, chiudi (ignora il canale)
       non risolto  -> resta in listen() col timeout di sicurezza a 300s
```

## User Stories

1. As a developer, I want the SSE endpoint to stop polling the database every 2 seconds per open connection, so that the database load no longer scales linearly with the number of users waiting for enrichment.
2. As a developer, I want the publish to happen only after the database transaction that writes the terminal state has committed, so that a subscriber never receives a notification before the corresponding data is actually visible to a query.
3. As a developer, I want the subscription to be established before checking the current database state, so that a state transition happening in the exact window between connecting and subscribing can never be missed (Pub/Sub has no buffering or replay).
4. As a developer, I want the existing 300-second safety timeout preserved even though polling is gone, so that a connection can't hang forever if no terminal event is ever published (e.g. an out-of-scope failure mode like abandoned raw ingestion).
5. As a Proprietario del Viaggio, I want the app's notification behavior to be unaffected by this change, so that switching the underlying mechanism doesn't introduce any new failure mode or change to what I see.

## Implementation Decisions

- Un canale Redis per trip, `diary_status:{trip_id}` — non un canale unico filtrato lato consumer. Ogni sottoscrittore riceve solo i messaggi che lo riguardano; l'overhead resta legato all'attesa del singolo utente, non al traffico totale della piattaforma.
- Il payload pubblicato è lo stesso identico JSON che oggi finisce nel campo `data:` dell'evento SSE — l'endpoint lo ritrasmette così com'è, senza ricostruirlo. Nome del canale e formato del payload vivono in un unico modulo condiviso, importato sia dal lato publisher (task Celery, sincrono) sia dal lato subscriber (endpoint ASGI, asincrono), per evitare derive indipendenti dello stesso pattern.
- Pubblicazione tramite `transaction.on_commit(...)` subito dopo la scrittura dello stato terminale — mai prima, per evitare che un sottoscrittore riceva la notifica mentre la transazione non è ancora visibile a una nuova query.
- Sequenza race-safe obbligata nell'endpoint: `SUBSCRIBE` prima di tutto, poi un solo controllo del DB. Se già risolto, emetti subito e chiudi senza mai entrare in `listen()`. Altrimenti resta in `listen()` sul canale già aperto. Redis Pub/Sub non bufferizza: un messaggio pubblicato prima della subscribe va perso per sempre, quindi questa sequenza è l'unico modo di chiudere la finestra di rischio senza un doppio controllo del DB.
- Connessione Redis dedicata per richiesta SSE, nessun pool condiviso: ogni richiesta in attesa deve comunque tenere bloccata una connessione in `listen()` per tutta la durata dell'attesa (fino a 300s); un pool condiviso aiuterebbe solo a riusare connessioni tra richieste sequenziali, non a condividerle durante l'attesa.
- Client sincrono (`redis.Redis`) lato publisher (il task Celery è sincrono), client asincrono (`redis.asyncio.Redis`) lato subscriber (l'endpoint è ASGI). Connessione aperta e chiusa per singola pubblicazione lato publisher — evento raro, non un hot path.
- Il timeout di sicurezza di 300 secondi (`_TRIP_EVENT_MAX_SECONDS`) viene preservato avvolgendo il `listen()` in `asyncio.wait_for(..., timeout=max_seconds)`, per il caso (fuori scope) in cui nessun evento terminale venga mai pubblicato.
- Nessun fallback automatico a polling se la `SUBSCRIBE` iniziale o la connessione a Redis fallisce: l'eccezione si propaga, la connessione SSE si chiude, il client la riapre con un nuovo `load()` (regola già decisa in `PIANO_SSE_EVENTI_DIARIO.md`). Motivo: Redis è già un requisito hard per il funzionamento del sistema (è il broker di Celery) — se è giù, l'arricchimento non viene comunque prodotto, quindi un secondo percorso di codice (polling) non avrebbe beneficio reale.
- Più sottoscrittori sullo stesso trip (stesso utente su più device) sono gestiti gratuitamente dal fan-out nativo di Redis Pub/Sub — nessuna logica aggiuntiva richiesta, nessun cambiamento di comportamento rispetto a oggi.

## Testing Decisions

- Test su Redis reale (quello già presente in `back-end/infra/docker-compose.yml`, stessa porta di `REDIS_URL`), nessuna nuova dev-dependency come `fakeredis`. Il progetto non ha CI automatizzata e Redis è già un requisito per girare la suite in locale (serve comunque per Celery); le semantiche di blocking `listen()` non sono garantite identiche al 100% con un fake.
- I test esistenti che chiamano `_trip_diary_event_stream(..., poll_seconds=0, max_seconds=10)` vanno riscritti, perché il parametro `poll_seconds` smette di esistere: il test pubblica sul canale Redis reale dopo aver avviato l'async generator e atteso che si sia sottoscritto, poi consuma lo stream e verifica l'evento emesso.
- Nuovo test dedicato alla race: il trip è già risolto nel DB prima ancora di aprire lo stream → l'evento deve uscire immediatamente, senza dipendere da una pubblicazione che non arriverà mai.
- Nuovo test sul timeout: nessuna pubblicazione e DB non risolto entro `max_seconds` → `": timeout\n\n"`, come oggi.
- Riusare i fixture di test già esistenti (`auth_headers`, `create_trip`, `_read_streaming_body`).

## Out of Scope

- Qualunque cambiamento al contratto SSE verso il client (resta quello di `PIANO_SSE_EVENTI_DIARIO.md`/`docs/prd/sse-diary-status-events.md`).
- Rilevamento di Raw Sensor Ingestion abbandonata (nessun evento terminale viene mai pubblicato in quel caso) — resta gestito dal solo timeout di sicurezza, come già documentato fuori scope nel piano SSE.
- Introduzione di un pool di connessioni Redis condiviso.
- Un fallback automatico a polling in caso di indisponibilità di Redis.
- `fakeredis` o altri meccanismi di mock del broker per i test.

## Further Notes

Decisioni scartate (per memoria):

- **Canale Redis unico con filtro lato consumer**: scartato — ogni sottoscrittore dovrebbe deserializzare/scartare i messaggi di tutti i trip in elaborazione, overhead legato al traffico totale della piattaforma invece che alla singola attesa.
- **Pool di connessioni Redis condiviso lato subscriber**: scartato — ogni richiesta SSE in attesa deve comunque tenere bloccata una connessione dedicata in `listen()`, quindi il pool non condividerebbe nulla durante l'attesa, solo complessità in più.
- **Fallback automatico a polling se Redis non risponde**: scartato — Redis è già un requisito hard per Celery; se è giù, l'arricchimento non viene comunque prodotto.
- **`fakeredis` per isolare i test dal Redis reale**: scartato — nessuna CI automatizzata, Redis già un requisito per girare la suite in locale.

Piano operativo dettagliato (file-by-file, passo-passo) in [`PIANO_REDIS_PUBSUB_DIARIO.md`](../../PIANO_REDIS_PUBSUB_DIARIO.md).
