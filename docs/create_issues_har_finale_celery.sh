#!/usr/bin/env bash
# Crea la parent issue e le issue verticali per "HAR finale asincrono via Celery".
# Prerequisiti:
#   1) gh installato
#   2) gh auth login con accesso a jackw1-tech/Mobility-Diary
# Esecuzione:
#   bash docs/create_issues_har_finale_celery.sh
set -euo pipefail

REPO="jackw1-tech/Mobility-Diary"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

gh label create feature --repo "$REPO" --color 0e8a16 --description "Nuova funzionalita" 2>/dev/null || true
gh label create backend --repo "$REPO" --color 1d76db --description "Back-end Django/PostGIS" 2>/dev/null || true
gh label create mobile --repo "$REPO" --color 5319e7 --description "App Flutter mobile/diary" 2>/dev/null || true
gh label create chore --repo "$REPO" --color cccccc --description "Manutenzione" 2>/dev/null || true
gh label create ready-for-agent --repo "$REPO" --color 2ea44f --description "Issue pronta per essere presa da un agente" 2>/dev/null || true

PARENT_URL="$(gh issue create --repo "$REPO" \
  --title "PRD: HAR finale asincrono via Celery" \
  --label feature --label backend --label mobile --label ready-for-agent \
  --body-file PRD_HAR_FINALE_CELERY.md)"

cat > "$TMP_DIR/issue-1.md" <<EOF
## Parent

$PARENT_URL

## What to build

Rendere esplicita la nuova semantica della Raw Sensor Ingestion: RECEIVED significa che l'Evidenza Sensoriale Grezza e nel bucket, mentre COMPLETED significa che il Diario della Mobilita e stato arricchito. Il mobile non deve piu chiudere il SyncJob raw quando vede RECEIVED; deve restare in attesa di processing backend.

## Acceptance criteria

- [ ] Backend: la status API rende distinguibili raw ricevuto, in coda, in processing, completato, failed retryable e failed final.
- [ ] Backend: i test documentano che raw_status=RECEIVED non rappresenta diario arricchito.
- [ ] Mobile: rawStatus == RECEIVED non viene piu considerato done.
- [ ] Mobile: il SyncJob resta claimable/pollabile finche il backend non restituisce raw_status=COMPLETED o uno stato terminale di errore.
- [ ] Mobile: test con API fake coprono RECEIVED, QUEUED, PROCESSING, COMPLETED, FAILED_RETRYABLE e FAILED_FINAL.

## Blocked by

None - can start immediately
EOF
ISSUE_1_URL="$(gh issue create --repo "$REPO" \
  --title "Raw Sensor Ingestion: RECEIVED non e completato" \
  --label feature --label backend --label mobile --label ready-for-agent \
  --body-file "$TMP_DIR/issue-1.md")"

cat > "$TMP_DIR/issue-2.md" <<EOF
## Parent

$PARENT_URL

## What to build

Trasformare complete-raw nel punto event-driven che avvia l'Arricchimento del Viaggio. Quando tutte le parti raw dichiarate sono confermate, il backend porta la fase raw a QUEUED, crea o collega un HarJob finale, e accoda il task Celery dopo il commit della transazione.

## Acceptance criteria

- [ ] complete-raw rifiuta la richiesta se il Core Ingestion non e completato.
- [ ] complete-raw rifiuta la richiesta se mancano parti raw dichiarate.
- [ ] Quando tutte le parti raw sono presenti, raw_status passa a QUEUED.
- [ ] L'enqueue Celery avviene con transaction.on_commit.
- [ ] Chiamate ripetute a complete-raw sono idempotenti per stati QUEUED, PROCESSING, COMPLETED e FAILED_RETRYABLE.
- [ ] I test verificano status transition, idempotenza e che non parta inference dentro la request HTTP.

## Blocked by

- $ISSUE_1_URL
EOF
ISSUE_2_URL="$(gh issue create --repo "$REPO" \
  --title "complete-raw accoda il job HAR finale" \
  --label feature --label backend --label ready-for-agent \
  --body-file "$TMP_DIR/issue-2.md")"

cat > "$TMP_DIR/issue-3.md" <<EOF
## Parent

$PARENT_URL

## What to build

Implementare il percorso worker che prende una TripIngestion raw queued, scarica le parti sensor_windows confermate dall'object storage, decomprime i JSON gzip, valida le finestre e produce una lista ordinata di finestre in memoria. Le matrici raw non devono diventare righe Postgres del diario.

## Acceptance criteria

- [ ] Il worker legge le parti raw confermate in ordine di sequence.
- [ ] Il worker supporta il formato windows con samples o matrix.
- [ ] La validazione intercetta gzip invalido, JSON invalido, timestamp mancanti, sample count incoerente, sample rate non positivo e shape matrice invalida.
- [ ] Le finestre valide vengono restituite in memoria con start, end, sample rate, sample count e matrice.
- [ ] Nessuna matrice raw viene persistita come dato primario del diario.
- [ ] Test backend fakeano object storage e coprono successi e input invalidi.

## Blocked by

- $ISSUE_2_URL
EOF
ISSUE_3_URL="$(gh issue create --repo "$REPO" \
  --title "Il worker legge le finestre raw dal bucket" \
  --label feature --label backend --label ready-for-agent \
  --body-file "$TMP_DIR/issue-3.md")"

cat > "$TMP_DIR/issue-4.md" <<EOF
## Parent

$PARENT_URL

## What to build

Usare predizioni HAR fake/deterministiche per chiudere il percorso prodotto: FSM, GPS e HAR vengono fusi dal backend usando il tempo come righello comune. Le StateTransition definiscono macro-intervalli stop/move, HAR assegna Etichette di Attivita dentro i move, GPS fornisce distanza/geometria, e il worker rigenera Segmenti di Mobilita e Luoghi Significativi in modo idempotente.

## Acceptance criteria

- [ ] Il worker porta raw_status a PROCESSING durante l'elaborazione.
- [ ] Le StateTransition generano macro-span STOP/MOVE.
- [ ] Gli STOP diventano Segmenti di Mobilita IDLE e possono referenziare Luoghi Significativi.
- [ ] I MOVE vengono divisi da cambi HAR significativi dopo smoothing/merge dei cambi troppo brevi.
- [ ] GPS point e HAR window con timestamp/cadenze diverse vengono selezionati per overlap temporale.
- [ ] Re-run dello stesso job cancella e rigenera i segmenti derivati senza duplicarli.
- [ ] A successo, Trip diventa processed, HarJob diventa success e raw_status=COMPLETED.
- [ ] Test coprono mismatched timestamps tra StateTransition, GPS, HAR windows e Segmenti di Mobilita derivati.

## Blocked by

- $ISSUE_3_URL
EOF
ISSUE_4_URL="$(gh issue create --repo "$REPO" \
  --title "HAR rigenera il Diario della Mobilita con fusione temporale" \
  --label feature --label backend --label ready-for-agent \
  --body-file "$TMP_DIR/issue-4.md")"

cat > "$TMP_DIR/issue-5.md" <<EOF
## Parent

$PARENT_URL

## What to build

Persistire la geometria derivata dei Segmenti di Mobilita di movimento. Ogni segmento MOVE deve avere un path PostGIS LineString costruito dai GPS point dentro l'intervallo temporale del segmento. Gli STOP non inventano una LineString: espongono Luoghi Significativi con centro, raggio e dwell.

## Acceptance criteria

- [ ] MobilitySegment supporta un path geografico nullable per i segmenti di movimento.
- [ ] Per ogni MOVE con almeno due punti GPS, il worker salva una LineString PostGIS ordinata per timestamp.
- [ ] Per MOVE senza geometria sufficiente, il segmento resta valido ma senza path disegnabile.
- [ ] Per STOP, il segmento usa place quando disponibile e non richiede path.
- [ ] distance_meters del segmento viene derivato dalla geometria del segmento quando disponibile.
- [ ] Test backend verificano path segmentato, stop senza path, distanza e idempotenza della rigenerazione.

## Blocked by

- $ISSUE_4_URL
EOF
ISSUE_5_URL="$(gh issue create --repo "$REPO" \
  --title "Segmenti di Mobilita persistono path PostGIS" \
  --label feature --label backend --label ready-for-agent \
  --body-file "$TMP_DIR/issue-5.md")"

cat > "$TMP_DIR/issue-6.md" <<EOF
## Parent

$PARENT_URL

## What to build

Esporre un read model backend per il Diario della Mobilita segmentato, adatto alla UI. La risposta deve permettere al frontend di disegnare una mappa segmentata: segmenti MOVE con Etichetta di Attivita e geometria, segmenti STOP con luogo/raggio/dwell, stato di enrichment e casi non ancora processati.

## Acceptance criteria

- [ ] Il backend espone un endpoint o estende l'endpoint diario con segmenti e geometria map-ready.
- [ ] La risposta include stato diary/enrichment, segmenti ordinati, label, intervalli temporali, distanza, geometria MOVE e place STOP.
- [ ] L'endpoint e filtrato per utente autenticato.
- [ ] Prima dell'arricchimento, la risposta rappresenta chiaramente lo stato not-yet-enriched senza fingere segmenti AI.
- [ ] Dopo l'arricchimento, la risposta deriva dai Segmenti di Mobilita persistiti e non ricalcola logica HAR lato request.
- [ ] Test API coprono not enriched, enriched with movement geometry, enriched with stop/place, user isolation.

## Blocked by

- $ISSUE_5_URL
EOF
ISSUE_6_URL="$(gh issue create --repo "$REPO" \
  --title "Read model segmentato per mappa e diario" \
  --label feature --label backend --label mobile --label ready-for-agent \
  --body-file "$TMP_DIR/issue-6.md")"

cat > "$TMP_DIR/issue-7.md" <<EOF
## Parent

$PARENT_URL

## What to build

Il mobile scopre il completamento HAR con polling controllato. Mentre raw_status e QUEUED o PROCESSING, la UI puo mostrare traccia base e stato analisi in corso. Quando il backend arriva a COMPLETED, il client ricarica il read model segmentato e passa alla visualizzazione con segmenti colorati e soste/luoghi.

## Acceptance criteria

- [ ] Il mobile poll-a ingestion status quando conosce remoteIngestionId.
- [ ] Il polling usa backoff/ritardi gia coerenti con SyncJob e non martella il backend.
- [ ] Al completamento raw, il mobile refetch-a il read model segmentato.
- [ ] La mappa mostra la traccia base mentre l'analisi e in corso e la mappa segmentata quando il diario e arricchito.
- [ ] Errori FAILED_RETRYABLE e FAILED_FINAL sono rappresentati senza perdere il Viaggio Sincronizzato.
- [ ] Test mobile coprono transizione da processing a completed e refresh del read model segmentato.

## Blocked by

- $ISSUE_6_URL
EOF
ISSUE_7_URL="$(gh issue create --repo "$REPO" \
  --title "Frontend polling fino a diario arricchito" \
  --label feature --label mobile --label ready-for-agent \
  --body-file "$TMP_DIR/issue-7.md")"

cat > "$TMP_DIR/issue-8.md" <<EOF
## Parent

$PARENT_URL

## What to build

Inserire il modello HAR reale nel punto gia preparato. Il worker carica lazy i modelli Keras CNN 1D e GRU, proietta le finestre raw 500x9 ai primi sei canali, gestisce sequenze da 32 finestre e restituisce Etichette di Attivita con confidenza. DRIVING viene mappato nel vocabolario del diario come MOVING_VEHICLE.

## Acceptance criteria

- [ ] Il worker runtime include le dipendenze necessarie per TensorFlow/Keras.
- [ ] Gli artifact del modello sono disponibili al worker e caricati lazy/cache per processo.
- [ ] L'adapter accetta finestre 500x9 e passa al modello solo accelerometro+giroscopio.
- [ ] Sequenze piu corte di 32 finestre vengono gestite con padding coerente.
- [ ] Le classi modello vengono mappate al vocabolario ActivityLabel esistente.
- [ ] HarJob.result registra classifier/model metadata, conteggio finestre, distribuzione label e confidence summary quando disponibile.
- [ ] Test stretti dell'adapter coprono shape, mapping e fallback senza rendere i test ordinari dipendenti da inferenza lenta.

## Blocked by

- $ISSUE_3_URL
- $ISSUE_4_URL
EOF
ISSUE_8_URL="$(gh issue create --repo "$REPO" \
  --title "Adapter Keras CNN+GRU per Etichette di Attivita" \
  --label feature --label backend --label ready-for-agent \
  --body-file "$TMP_DIR/issue-8.md")"

cat > "$TMP_DIR/issue-9.md" <<EOF
## Parent

$PARENT_URL

## What to build

Indurire il flusso HAR finale. Errori temporanei devono diventare FAILED_RETRYABLE e permettere retry Celery; errori definitivi diventano FAILED_FINAL. I raw nel bucket non vengono cancellati ne dopo failure ne dopo successo in questa fase del progetto.

## Acceptance criteria

- [ ] Errori retryable salvano errore su HarJob/TripIngestion e portano raw a FAILED_RETRYABLE.
- [ ] Dopo retry esauriti o input strutturalmente invalido, raw diventa FAILED_FINAL.
- [ ] Nessun failure path cancella raw object storage.
- [ ] Anche dopo successo HAR, i raw restano conservati con cleanup disabilitato.
- [ ] Il mobile non richiede re-upload raw per failure backend-side retryable.
- [ ] Test coprono storage failure, model failure, invalid payload, retry exhausted e no cleanup.

## Blocked by

- $ISSUE_2_URL
- $ISSUE_3_URL
EOF
ISSUE_9_URL="$(gh issue create --repo "$REPO" \
  --title "Retry, failure e retention raw per HAR finale" \
  --label feature --label backend --label mobile --label ready-for-agent \
  --body-file "$TMP_DIR/issue-9.md")"

cat <<EOF
Fatto. Issue create su $REPO:
Parent: $PARENT_URL
1: $ISSUE_1_URL
2: $ISSUE_2_URL
3: $ISSUE_3_URL
4: $ISSUE_4_URL
5: $ISSUE_5_URL
6: $ISSUE_6_URL
7: $ISSUE_7_URL
8: $ISSUE_8_URL
9: $ISSUE_9_URL
EOF
