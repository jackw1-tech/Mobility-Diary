# Issue verticali - HAR finale asincrono via Celery

Derivate da `PRD_HAR_FINALE_CELERY.md`.

Le slice sono tracer bullet in ordine di dipendenza. Ogni issue deve produrre un
percorso verificabile end-to-end, mantenendo il backend come source of truth per
Raw Sensor Ingestion, Arricchimento del Viaggio, Segmenti di Mobilita e mappa
segmentata.

## Issue 1 - Raw Sensor Ingestion: RECEIVED non e completato

**Blocked by**: None - can start immediately

**User stories covered**: 5, 20, 21, 33, 35, 41

## What to build

Rendere esplicita la nuova semantica della Raw Sensor Ingestion: `RECEIVED`
significa che l'Evidenza Sensoriale Grezza e nel bucket, mentre `COMPLETED`
significa che il Diario della Mobilita e stato arricchito. Il mobile non deve
piu chiudere il SyncJob raw quando vede `RECEIVED`; deve restare in attesa di
processing backend.

## Acceptance criteria

- [ ] Backend: la status API rende distinguibili raw ricevuto, in coda, in processing, completato, failed retryable e failed final.
- [ ] Backend: i test documentano che `raw_status=RECEIVED` non rappresenta diario arricchito.
- [ ] Mobile: `rawStatus == RECEIVED` non viene piu considerato done.
- [ ] Mobile: il SyncJob resta claimable/pollabile finche il backend non restituisce `raw_status=COMPLETED` o uno stato terminale di errore.
- [ ] Mobile: test con API fake coprono `RECEIVED`, `QUEUED`, `PROCESSING`, `COMPLETED`, `FAILED_RETRYABLE` e `FAILED_FINAL`.

## Issue 2 - complete-raw accoda il job HAR finale

**Blocked by**: Issue 1

**User stories covered**: 4, 16, 17, 20, 21

## What to build

Trasformare `complete-raw` nel punto event-driven che avvia l'Arricchimento del
Viaggio. Quando tutte le parti raw dichiarate sono confermate, il backend porta
la fase raw a `QUEUED`, crea o collega un HarJob finale, e accoda il task Celery
dopo il commit della transazione.

## Acceptance criteria

- [ ] `complete-raw` rifiuta la richiesta se il Core Ingestion non e completato.
- [ ] `complete-raw` rifiuta la richiesta se mancano parti raw dichiarate.
- [ ] Quando tutte le parti raw sono presenti, `raw_status` passa a `QUEUED`.
- [ ] L'enqueue Celery avviene con `transaction.on_commit`.
- [ ] Chiamate ripetute a `complete-raw` sono idempotenti per stati `QUEUED`, `PROCESSING`, `COMPLETED` e `FAILED_RETRYABLE`.
- [ ] I test verificano status transition, idempotenza e che non parta inference dentro la request HTTP.

## Issue 3 - Il worker legge le finestre raw dal bucket

**Blocked by**: Issue 2

**User stories covered**: 6, 18, 28, 31, 32

## What to build

Implementare il percorso worker che prende una TripIngestion raw queued,
scarica le parti `sensor_windows` confermate dall'object storage, decomprime i
JSON gzip, valida le finestre e produce una lista ordinata di finestre in
memoria. Le matrici raw non devono diventare righe Postgres del diario.

## Acceptance criteria

- [ ] Il worker legge le parti raw confermate in ordine di sequence.
- [ ] Il worker supporta il formato `windows` con `samples` o `matrix`.
- [ ] La validazione intercetta gzip invalido, JSON invalido, timestamp mancanti, sample count incoerente, sample rate non positivo e shape matrice invalida.
- [ ] Le finestre valide vengono restituite in memoria con start, end, sample rate, sample count e matrice.
- [ ] Nessuna matrice raw viene persistita come dato primario del diario.
- [ ] Test backend fakeano object storage e coprono successi e input invalidi.

## Issue 4 - HAR rigenera il Diario della Mobilita con fusione temporale

**Blocked by**: Issue 3

**User stories covered**: 1, 3, 7, 8, 9, 10, 11, 22, 23, 29, 43, 45

## What to build

Usare predizioni HAR fake/deterministiche per chiudere il percorso prodotto:
FSM, GPS e HAR vengono fusi dal backend usando il tempo come righello comune.
Le StateTransition definiscono macro-intervalli stop/move, HAR assegna Etichette
di Attivita dentro i move, GPS fornisce distanza/geometria, e il worker
rigenera Segmenti di Mobilita e Luoghi Significativi in modo idempotente.

## Acceptance criteria

- [ ] Il worker porta `raw_status` a `PROCESSING` durante l'elaborazione.
- [ ] Le StateTransition generano macro-span STOP/MOVE.
- [ ] Gli STOP diventano Segmenti di Mobilita `IDLE` e possono referenziare Luoghi Significativi.
- [ ] I MOVE vengono divisi da cambi HAR significativi dopo smoothing/merge dei cambi troppo brevi.
- [ ] GPS point e HAR window con timestamp/cadenze diverse vengono selezionati per overlap temporale.
- [ ] Re-run dello stesso job cancella e rigenera i segmenti derivati senza duplicarli.
- [ ] A successo, Trip diventa processed, HarJob diventa success e `raw_status=COMPLETED`.
- [ ] Test coprono mismatched timestamps tra StateTransition, GPS, HAR windows e Segmenti di Mobilita derivati.

## Issue 5 - Segmenti di Mobilita persistono path PostGIS

**Blocked by**: Issue 4

**User stories covered**: 38, 40, 42, 44, 45, 46

## What to build

Persistire la geometria derivata dei Segmenti di Mobilita di movimento. Ogni
segmento MOVE deve avere un path PostGIS LineString costruito dai GPS point
dentro l'intervallo temporale del segmento. Gli STOP non inventano una
LineString: espongono Luoghi Significativi con centro, raggio e dwell.

## Acceptance criteria

- [ ] `MobilitySegment` supporta un path geografico nullable per i segmenti di movimento.
- [ ] Per ogni MOVE con almeno due punti GPS, il worker salva una LineString PostGIS ordinata per timestamp.
- [ ] Per MOVE senza geometria sufficiente, il segmento resta valido ma senza path disegnabile.
- [ ] Per STOP, il segmento usa `place` quando disponibile e non richiede path.
- [ ] `distance_meters` del segmento viene derivato dalla geometria del segmento quando disponibile.
- [ ] Test backend verificano path segmentato, stop senza path, distanza e idempotenza della rigenerazione.

## Issue 6 - Read model segmentato per mappa e diario

**Blocked by**: Issue 5

**User stories covered**: 37, 38, 39, 40, 42, 46

## What to build

Esporre un read model backend per il Diario della Mobilita segmentato, adatto
alla UI. La risposta deve permettere al frontend di disegnare una mappa
segmentata: segmenti MOVE con Etichetta di Attivita e geometria, segmenti STOP
con luogo/raggio/dwell, stato di enrichment e casi non ancora processati.

## Acceptance criteria

- [ ] Il backend espone un endpoint o estende l'endpoint diario con segmenti e geometria map-ready.
- [ ] La risposta include stato diary/enrichment, segmenti ordinati, label, intervalli temporali, distanza, geometria MOVE e place STOP.
- [ ] L'endpoint e filtrato per utente autenticato.
- [ ] Prima dell'arricchimento, la risposta rappresenta chiaramente lo stato not-yet-enriched senza fingere segmenti AI.
- [ ] Dopo l'arricchimento, la risposta deriva dai Segmenti di Mobilita persistiti e non ricalcola logica HAR lato request.
- [ ] Test API coprono not enriched, enriched with movement geometry, enriched with stop/place, user isolation.

## Issue 7 - Frontend polling fino a diario arricchito

**Blocked by**: Issue 6

**User stories covered**: 5, 37, 38, 39, 41, 46

## What to build

Il mobile scopre il completamento HAR con polling controllato. Mentre
`raw_status` e `QUEUED` o `PROCESSING`, la UI puo mostrare traccia base e stato
analisi in corso. Quando il backend arriva a `COMPLETED`, il client ricarica il
read model segmentato e passa alla visualizzazione con segmenti colorati e
soste/luoghi.

## Acceptance criteria

- [ ] Il mobile poll-a ingestion status quando conosce `remoteIngestionId`.
- [ ] Il polling usa backoff/ritardi gia coerenti con SyncJob e non martella il backend.
- [ ] Al completamento raw, il mobile refetch-a il read model segmentato.
- [ ] La mappa mostra la traccia base mentre l'analisi e in corso e la mappa segmentata quando il diario e arricchito.
- [ ] Errori `FAILED_RETRYABLE` e `FAILED_FINAL` sono rappresentati senza perdere il Viaggio Sincronizzato.
- [ ] Test mobile coprono transizione da processing a completed e refresh del read model segmentato.

## Issue 8 - Adapter Keras CNN+GRU per Etichette di Attivita

**Blocked by**: Issue 3, Issue 4

**User stories covered**: 2, 13, 14, 24, 25, 26, 27

## What to build

Inserire il modello HAR reale nel punto gia preparato. Il worker carica lazy i
modelli Keras CNN 1D e GRU, proietta le finestre raw 500x9 ai primi sei canali,
gestisce sequenze da 32 finestre e restituisce Etichette di Attivita con
confidenza. `DRIVING` viene mappato nel vocabolario del diario come
`MOVING_VEHICLE`.

## Acceptance criteria

- [ ] Il worker runtime include le dipendenze necessarie per TensorFlow/Keras.
- [ ] Gli artifact del modello sono disponibili al worker e caricati lazy/cache per processo.
- [ ] L'adapter accetta finestre 500x9 e passa al modello solo accelerometro+giroscopio.
- [ ] Sequenze piu corte di 32 finestre vengono gestite con padding coerente.
- [ ] Le classi modello vengono mappate al vocabolario ActivityLabel esistente.
- [ ] `HarJob.result` registra classifier/model metadata, conteggio finestre, distribuzione label e confidence summary quando disponibile.
- [ ] Test stretti dell'adapter coprono shape, mapping e fallback senza rendere i test ordinari dipendenti da inferenza lenta.

## Issue 9 - Retry, failure e retention raw per HAR finale

**Blocked by**: Issue 2, Issue 3

**User stories covered**: 6, 12, 17, 18, 19, 34

## What to build

Indurire il flusso HAR finale. Errori temporanei devono diventare
`FAILED_RETRYABLE` e permettere retry Celery; errori definitivi diventano
`FAILED_FINAL`. I raw nel bucket non vengono cancellati ne dopo failure ne dopo
successo in questa fase del progetto.

## Acceptance criteria

- [ ] Errori retryable salvano errore su HarJob/TripIngestion e portano raw a `FAILED_RETRYABLE`.
- [ ] Dopo retry esauriti o input strutturalmente invalido, raw diventa `FAILED_FINAL`.
- [ ] Nessun failure path cancella raw object storage.
- [ ] Anche dopo successo HAR, i raw restano conservati con cleanup disabilitato.
- [ ] Il mobile non richiede re-upload raw per failure backend-side retryable.
- [ ] Test coprono storage failure, model failure, invalid payload, retry exhausted e no cleanup.

