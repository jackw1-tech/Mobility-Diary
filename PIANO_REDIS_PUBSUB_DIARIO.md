# Piano: sostituzione del polling SSE con Redis Pub/Sub

> Nota sulla compatibilita' di rilascio: come per il piano precedente (`PIANO_SSE_EVENTI_DIARIO.md`), il progetto e' ancora in sviluppo senza utenti reali da proteggere — possiamo permetterci un cutover diretto, senza fallback retro-compatibili, se la soluzione lo richiede.

## 1. Contesto

L'endpoint `GET /mobility/trips/{id}/events` (`back-end/ninja/mobility/api.py:182-213`) oggi notifica l'app via SSE facendo **polling sul database** ogni `_TRIP_EVENT_POLL_SECONDS = 2` secondi (`api.py:36`), per un massimo di `_TRIP_EVENT_MAX_SECONDS = 300` secondi (`api.py:37`):

```python
async def _trip_diary_event_stream(trip_id, user_id, *, poll_seconds=2, max_seconds=300):
    deadline = time.monotonic() + max_seconds
    while True:
        if await _is_trip_diary_processed(trip_id, user_id):
            yield _sse_event("diary_enriched", {"trip_id": trip_id})
            return
        if time.monotonic() >= deadline:
            yield ": timeout\n\n"
            return
        yield ": waiting\n\n"
        await asyncio.sleep(poll_seconds)
```

Ogni connessione SSE aperta genera una query al DB ogni 2 secondi per tutta la durata dell'attesa (fino a 150 query per connessione nel caso peggiore di 300s). Con N utenti che aspettano contemporaneamente l'arricchimento del proprio diario, il carico sul DB scala linearmente con N, anche se in pratica la maggior parte delle query non trova nulla di nuovo.

> Questo piano si lega alla [issue 02](.scratch/sse-diary-status-events/issues/02-surface-diary-enrichment-failure.md) e alla relativa PRD: quel lavoro introduce anche il rilevamento del fallimento (`TripIngestion.raw_status == FAILED_FINAL`), che andra' anch'esso convertito a pub/sub se gia' implementato a polling quando questo piano viene eseguito.

Infrastruttura gia' presente (verificata nel codice):

- `REDIS_URL` e `CELERY_BROKER_URL` sono gia' configurati (`config/settings.py:155-157`) e puntano alla stessa istanza Redis usata da Celery come broker.
- Il pacchetto `redis>=5.0,<6.0` e' gia' una dipendenza del progetto (incluso `redis.asyncio`, disponibile dalla 4.2+).
- Lo stato terminale (`Trip.status = PROCESSED` o `TripIngestion.raw_status = FAILED_FINAL`) viene scritto da codice **sincrono** Celery (`tasks.py`, dentro `process_trip_har_final` / `run_pipeline`), non dal processo ASGI che serve l'SSE.

## 2. Stato attuale (cosa NON cambia)

- Il contratto SSE verso l'app (evento `diary_status`, `data.status` = `enriched`/`failed`/`reason`) resta quello descritto in `PIANO_SSE_EVENTI_DIARIO.md` — questo piano cambia solo **come il backend scopre** che lo stato e' cambiato, non cosa manda al client.
- `GET /diary` resta l'unica fonte di verita' per il contenuto del diario; l'SSE resta un campanello.

## 3. Cosa implementare (in discussione)

Sezione da costruire insieme. Domande aperte, in ordine di dipendenza:

1. ~~**Chi pubblica, e quando?**~~ **RISOLTO**: il task Celery che scrive lo stato terminale (`tasks.py`, dentro `process_trip_har_final`/`run_pipeline`) pubblica su Redis tramite `transaction.on_commit(...)`, mai prima — cosi' il messaggio non parte mai prima che il dato sia visibile a una nuova query (niente race con replica in lag o transazione non ancora committata).
2. ~~**Naming del canale**~~ **RISOLTO**: un canale per trip, `diary_status:{trip_id}`. Ogni sottoscrittore (= ogni SSE aperta) riceve solo i messaggi che lo riguardano, invece di dover deserializzare/scartare i messaggi di tutti i trip in elaborazione su un canale unico — l'overhead resta legato all'attesa del singolo utente, non al traffico totale della piattaforma.
3. ~~**La race del pub/sub**~~ **RISOLTO**: Redis Pub/Sub non bufferizza, quindi un messaggio pubblicato prima che il consumer si sia sottoscritto va perso per sempre. Sequenza obbligata nell'endpoint per chiudere la finestra di rischio:
   1. `SUBSCRIBE diary_status:{trip_id}` (apri prima il canale)
   2. Poi controlla lo stato attuale sul DB una volta (stesso controllo che oggi avviene nel loop di polling)
   3. Se già risolto al passo 2 → emetti subito l'evento e chiudi, ignorando il canale
   4. Altrimenti → resta in `listen()` sul canale già aperto, senza più interrogare il DB
   Cosi' o lo stato e' gia' risolto quando si controlla il DB (passo 2), o il canale e' gia' sottoscritto *prima* che possa arrivare qualunque pubblicazione futura — nessun doppio controllo DB necessario.
4. ~~**Lifecycle della connessione Redis**~~ **RISOLTO**: connessione dedicata per richiesta SSE (niente pool). Ogni richiesta che resta in attesa deve comunque tenere una connessione bloccata in `listen()` per tutta la durata dell'attesa (fino a 300s) — un pool condiviso aiuterebbe solo a riusare connessioni *tra* richieste sequenziali, non a condividerle *durante* l'attesa, quindi non vale la complessita' aggiuntiva. Apertura con `async with`/`try`-`finally` per garantire la chiusura della connessione anche in caso di disconnessione del client o eccezione.
5. ~~**Fallback se Redis non risponde**~~ **RISOLTO**: nessun fallback a polling. Se la `SUBSCRIBE` fallisce, l'eccezione si propaga, la connessione SSE si chiude e il client la rilancia con un nuovo `load()` (regola gia' decisa in `PIANO_SSE_EVENTI_DIARIO.md`). Motivo: Redis e' gia' un requisito hard per il funzionamento del sistema (e' il broker di Celery) — se Redis e' giu', l'arricchimento del diario non viene comunque prodotto, quindi un'SSE che fallisce nello stesso momento non introduce un nuovo single point of failure. Mantenere un doppio percorso di codice (pub/sub + polling) per un fallimento che blocca comunque l'intera pipeline non avrebbe beneficio reale.
6. ~~**Piu' sottoscrittori sullo stesso trip**~~ **RISOLTO**: stesso utente con app aperta su due device/tab → due `SUBSCRIBE` sullo stesso canale `diary_status:{trip_id}` → Redis fa fan-out nativo a entrambi, senza logica aggiuntiva. Nessun cambiamento di comportamento rispetto a oggi (col polling ogni connessione interroga il DB per conto proprio, indipendentemente dalle altre).
7. ~~**Strategia di test**~~ **RISOLTO**: Redis reale (quello gia' in `back-end/infra/docker-compose.yml`, stessa porta di `REDIS_URL`), nessuna nuova dev-dependency (`fakeredis` scartato). Il progetto non ha CI automatizzata e Redis e' gia' un requisito per girare la suite in locale (serve comunque per Celery), quindi non c'e' beneficio reale nell'isolare i test pub/sub dal Redis reale.

## 4. Piano operativo

### 4.1 Backend — modulo condiviso

Nuovo modulo (es. `mobility/realtime.py`) che e' la **singola fonte di verita'** per nome del canale e formato del messaggio, importato sia da `tasks.py` (che pubblica, sincrono) sia da `api.py` (che sottoscrive, asincrono) — evita che i due lati derivino in modo indipendente lo stesso pattern `diary_status:{trip_id}` o lo stesso schema di payload.

```python
def diary_status_channel(trip_id: int) -> str:
    return f"diary_status:{trip_id}"
```

Il payload pubblicato sul canale e' lo stesso identico JSON che oggi finisce nel campo `data:` dell'evento SSE (`{"trip_id": N, "status": "enriched"}` o `{"trip_id": N, "status": "failed", "reason": "..."}` — contratto definito in `PIANO_SSE_EVENTI_DIARIO.md`): l'endpoint SSE lo ritrasmette cosi' com'e' al client, senza ricostruirlo.

### 4.2 Backend — lato publisher (`tasks.py`)

Dentro `process_trip_har_final`/`run_pipeline`, dopo la scrittura dello stato terminale (`Trip.status = PROCESSED` o `TripIngestion.raw_status = FAILED_FINAL`):

```python
from django.db import transaction
import redis

def _publish_diary_status(trip_id: int, payload: dict) -> None:
    client = redis.Redis.from_url(settings.REDIS_URL)
    try:
        client.publish(diary_status_channel(trip_id), json.dumps(payload, separators=(",", ":")))
    finally:
        client.close()

transaction.on_commit(lambda: _publish_diary_status(trip_id, {"trip_id": trip_id, "status": "enriched"}))
```

Client sincrono (`redis.Redis`, non `redis.asyncio`) perche' il task Celery e' sincrono. Connessione aperta e chiusa per singola pubblicazione — e' un evento raro (una volta per trip arricchito/fallito), non un hot path, quindi non serve un pool qui.

### 4.3 Backend — lato subscriber (`api.py`)

Riscrivere `_trip_diary_event_stream` per:

1. Aprire `redis.asyncio.Redis.from_url(settings.REDIS_URL)` e un `pubsub()` su `diary_status_channel(trip_id)`.
2. **Sottoscriversi prima** (`await pubsub.subscribe(channel)`), poi controllare lo stato attuale sul DB una volta (riuso di `_is_trip_diary_processed`/dell'helper di rilevamento fallimento dalla issue 02) — se gia' risolto, emettere subito e chiudere senza mai entrare in `listen()`.
3. Se non ancora risolto, restare in `async for message in pubsub.listen()`, **avvolto in `asyncio.wait_for(..., timeout=max_seconds)`** per preservare il timeout di sicurezza a 300s anche col pub/sub (nel caso, fuori scope di questo piano, in cui nessun evento terminale venga mai pubblicato — es. raw ingestion abbandonata, gia' documentato come fuori scope in `PIANO_SSE_EVENTI_DIARIO.md`).
4. Su `asyncio.TimeoutError` → `yield ": timeout\n\n"` (stesso comportamento di oggi).
5. `finally`: chiudere sempre `pubsub` e la connessione Redis, anche se il client SSE si disconnette prima.
6. Nessun fallback a polling se la `SUBSCRIBE` iniziale fallisce (decisione §3.5) — l'eccezione si propaga e la StreamingHttpResponse termina, il client riapre con `load()`.

`_TRIP_EVENT_POLL_SECONDS` e il loop `await asyncio.sleep(poll_seconds)` vengono rimossi: non c'e' piu' polling.

### 4.4 Test

- Backend: i test esistenti che chiamano `_trip_diary_event_stream(..., poll_seconds=0, max_seconds=10)` vanno riscritti, perche' `poll_seconds` non esiste piu'. Nuovo pattern: il test pubblica sul canale Redis reale (`redis.Redis.from_url(settings.REDIS_URL).publish(...)`) *dopo* aver avviato l'async generator e atteso che si sia sottoscritto, poi consuma lo stream e verifica l'evento emesso.
- Nuovo test dedicato alla race (§3.3): il trip e' *gia'* `PROCESSED` nel DB prima ancora di aprire lo stream → l'evento deve uscire immediatamente senza dipendere da una pubblicazione che non arrivera' mai (verifica che il controllo "post-subscribe" sul DB funzioni anche se nessuno pubblica nulla).
- Nuovo test sul timeout: nessuna pubblicazione e DB non risolto entro `max_seconds` → `": timeout\n\n"`, come oggi.
- Riusare i fixture esistenti (`auth_headers`, `create_trip`, `_read_streaming_body`).

## 5. Decisioni scartate

- **Canale unico con filtro lato consumer** (invece di un canale per trip): scartato — ogni sottoscrittore dovrebbe deserializzare/scartare i messaggi di tutti i trip in elaborazione, overhead legato al traffico totale della piattaforma invece che alla singola attesa (§3.2).
- **Pool di connessioni Redis condiviso** per il subscriber: scartato — ogni richiesta SSE in attesa deve comunque tenere bloccata una connessione dedicata in `listen()`, quindi il pool non condividerebbe nulla durante l'attesa, solo complessita' in piu' (§3.4).
- **Fallback automatico a polling se Redis non risponde**: scartato — Redis e' gia' un requisito hard per Celery; se e' giu', l'arricchimento non viene comunque prodotto, quindi un secondo percorso di codice non avrebbe beneficio reale (§3.5).
- **`fakeredis` per isolare i test dal Redis reale**: scartato — nessuna CI automatizzata, Redis e' gia' un requisito per girare la suite in locale, e le semantiche di blocking `listen()` non sono garantite identiche al 100% (§3.7).
