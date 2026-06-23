# Issue verticali - Mobile Dettaglio Viaggio, Statistiche, Preferenza Privacy e SSE

Derivate da `docs/PRD_MOBILE_DIARY_STATS_PRIVACY.md`.

Le slice sono tracer bullet in ordine di dipendenza. Ogni issue deve essere
demoabile da sola o verificabile con test ad alto livello. Label logica:
`ready-for-agent`.

---

## Issue 1 - Core completato apre Dettaglio Viaggio con Mappa base

**Tipo:** feature · **Area:** mobile + backend · **Dipendenze:** nessuna

**Stato locale:** implementata. Verifica mobile passata; verifica backend scritta
ma non eseguibile in locale finche Postgres `localhost:5432` non e attivo.

**User stories covered:** 1, 2, 3, 4, 8, 24, 33, 36, 37, 40, 42

### What to build

Quando la Core Ingestion completa, il backend deve garantire che la risposta
contenga un `trip_id` materializzato. Il mobile deve salvare quel `remoteTripId`
e la UI deve aprire automaticamente il Dettaglio Viaggio una sola volta per quel
Viaggio.

Il Dettaglio Viaggio in questa prima slice puo contenere la shell a tab e la tab
Mappa, riusando la Traiettoria del Viaggio base gia disponibile. Se
l'Arricchimento del Viaggio non e ancora completo, la pagina mostra chiaramente
uno stato di analisi in corso senza bloccare la mappa base.

La SyncQueue non deve navigare direttamente: salva solo stato e identificativi.
La responsabilita della navigazione resta nella UI.

### Acceptance criteria

- [x] Il backend inline core non restituisce mai `core_status=COMPLETED` con
      `trip_id=null`.
- [x] Se il Core risultasse completato senza Trip materializzato, l'API fallisce
      esplicitamente invece di restituire una risposta ambigua.
- [x] Dopo una risposta Core completata, il mobile salva `remoteTripId`,
      `coreStatus=COMPLETED` e `coreMapAvailable`.
- [x] La Home osserva lo snapshot di sincronizzazione e apre il Dettaglio Viaggio
      quando vede un nuovo `remoteTripId` completato.
- [x] La navigazione automatica avviene una sola volta per lo stesso
      `remoteTripId`, anche se lo stato viene emesso piu volte.
- [x] Il Dettaglio Viaggio ha una shell con tab `Mappa`, `Diario`,
      `Statistiche`, ma in questa slice e sufficiente che la tab Mappa sia
      funzionante.
- [x] Se il diario non e ancora arricchito, la Mappa mostra la Traiettoria del
      Viaggio base e uno stato "analisi in corso".
- [x] Test backend coprono il contratto `core_status=COMPLETED => trip_id`.
- [x] Test mobile coprono navigazione automatica positiva, nessuna navigazione
      quando il Core non e completato, e guardia anti-navigazione duplicata.

### Verifica locale

- `flutter test test/features/acquisition/domain/acquisition_sync_snapshot_test.dart`
- `flutter analyze`
- `../.venv/bin/pytest mobility/tests/test_inline_core_ingestion_api.py::test_inline_core_completed_without_trip_is_explicit_conflict`
  non completato: Postgres locale rifiuta connessioni su `localhost:5432`.

### Blocked by

None - can start immediately.

---

## Issue 2 - Dettaglio Viaggio riceve evento SSE quando HAR arricchisce il diario

**Tipo:** feature · **Area:** backend + mobile · **Dipendenze:** Issue 1

**Stato locale:** implementata. Verifica mobile e test unitario del generator SSE
passati; test endpoint backend scritti ma non eseguibili in locale finche
Postgres `localhost:5432` non e attivo.

**User stories covered:** 5, 6, 7, 9, 34, 35, 41, 42

### What to build

Sostituire il polling aggressivo della pagina viaggio con uno stream SSE
foreground, aperto solo mentre il Dettaglio Viaggio e visibile e il Diario della
Mobilita non e ancora arricchito.

Il backend espone uno stream eventi per singolo Viaggio. Quando l'HAR finale
completa l'Arricchimento del Viaggio, il backend emette `diary_enriched`. Il
mobile usa l'evento solo come sveglia: dopo averlo ricevuto, ricarica il diary
read model dal backend e aggiorna la Mappa segmentata.

### Acceptance criteria

- [x] Il backend espone uno stream autenticato per singolo Viaggio con content
      type `text/event-stream`.
- [x] Lo stream e filtrato per utente: un utente non puo ascoltare eventi di un
      Viaggio altrui.
- [x] Lo stream emette un evento `diary_enriched` quando il Diario della Mobilita
      del Viaggio e gia arricchito o diventa arricchito durante l'ascolto.
- [x] Il payload evento contiene almeno il `trip_id`.
- [x] Il Dettaglio Viaggio apre lo stream solo se il read model del diario non e
      ancora processato.
- [x] Il Dettaglio Viaggio non apre lo stream se il diario e gia processato.
- [x] Alla ricezione di `diary_enriched`, il mobile ricarica
      `GET /trips/{id}/diary` e aggiorna lo stato della pagina.
- [x] Lo stream viene chiuso quando il Dettaglio Viaggio viene chiuso o quando
      il diario risulta arricchito.
- [x] Test backend coprono autorizzazione, content type, evento per diario gia
      pronto e user isolation.
- [x] Test mobile coprono evento ricevuto, refetch del diario e lifecycle dello
      stream.

### Verifica locale

- `flutter test test/state_management/cubits/trip_track_cubit_test.dart`
- `flutter test test/features/acquisition/domain/acquisition_sync_snapshot_test.dart test/state_management/cubits/trip_track_cubit_test.dart`
- `flutter analyze`
- `../.venv/bin/pytest mobility/tests/test_trip_track.py::test_trip_event_stream_emits_when_diary_becomes_processed`
- `../.venv/bin/python -m py_compile mobility/api.py mobility/tests/test_trip_track.py mobility/ingestion/api.py mobility/tests/test_inline_core_ingestion_api.py`
- I test endpoint backend che richiedono DB non completano finche Postgres
  locale rifiuta connessioni su `localhost:5432`.

### Blocked by

- Issue 1.

---

## Issue 3 - Timeline del Viaggio mostra il Diario della Mobilita

**Tipo:** feature · **Area:** mobile · **Dipendenze:** Issue 1

**Stato locale:** implementata. La tab Diario usa lo stesso `TripTrackCubit`
del Dettaglio Viaggio e legge i segmenti del read model `/diary`.

**User stories covered:** 10, 11, 12, 13, 14, 15, 16, 33, 40, 42

### What to build

Completare la tab Diario del Dettaglio Viaggio con una Timeline del Viaggio
derivata dai Segmenti di Mobilita gia esposti dal read model backend.

La timeline deve rendere il diario leggibile: ogni segmento mostra intervallo
orario, durata, tipo movimento/sosta, Etichetta di Attivita leggibile, distanza
per i movimenti e Luogo Significativo per le soste quando disponibile.

Prima dell'Arricchimento del Viaggio, la tab Diario mostra uno stato pending e
non inventa segmenti lato mobile.

### Acceptance criteria

- [x] La tab Diario legge i Segmenti di Mobilita dallo stesso read model usato
      dal Dettaglio Viaggio.
- [x] I segmenti sono mostrati in ordine temporale.
- [x] Ogni segmento mostra intervallo inizio/fine e durata.
- [x] I segmenti MOVE mostrano Etichetta di Attivita leggibile e distanza quando
      disponibile.
- [x] I segmenti STOP mostrano il Luogo Significativo quando disponibile; in
      assenza di place mostrano una sosta rilevata.
- [x] Le label tecniche del backend sono mappate in testo mobile coerente.
- [x] Prima dell'arricchimento, la tab Diario mostra stato pending senza dati
      semantici inventati.
- [x] Errori ed empty state sono gestiti senza crash.
- [x] Test mobile coprono timeline arricchita, pending state, empty/error state
      e mapping delle label.

### Verifica locale

- `flutter test test/state_management/cubits/trip_track_cubit_test.dart test/ui/pages/trip_diary_presenter_test.dart`
- `flutter analyze`
- `flutter test`

### Blocked by

- Issue 1.

---

## Issue 4 - Statistiche del Viaggio da Segmenti di Mobilita

**Tipo:** feature · **Area:** mobile · **Dipendenze:** Issue 3

**Stato locale:** implementata. Le statistiche sono calcolate lato mobile dai
segmenti del Diario della Mobilita e non introducono nuovi modelli backend.

**User stories covered:** 17, 18, 19, 20, 21, 22, 23, 24, 33, 40

### What to build

Completare la tab Statistiche del Dettaglio Viaggio con metriche calcolate lato
mobile dai Segmenti di Mobilita caricati dal read model.

Le Statistiche del Viaggio non sono un nuovo dato persistito. Sono una lettura
aggregata del Diario della Mobilita di un singolo Viaggio.

La UI mostra card numeriche e barre proporzionali per attivita.

### Acceptance criteria

- [x] La tab Statistiche calcola durata totale del Viaggio dai segmenti.
- [x] La tab Statistiche mostra distanza totale coerente con i segmenti o con il
      read model disponibile.
- [x] La tab Statistiche calcola tempo in movimento e tempo in sosta.
- [x] La tab Statistiche calcola tempo per Etichetta di Attivita.
- [x] La tab Statistiche mostra numero di soste o Luoghi Significativi.
- [x] Le statistiche sono presentate con card numeriche e barre per attivita.
- [x] Prima dell'arricchimento, la tab Statistiche mostra stato pending senza
      metriche semantiche finali.
- [x] Non viene aggiunto alcun modello backend per persistere queste statistiche.
- [x] Test mobile coprono calcolo durata, movimento/sosta, distanza, conteggio
      luoghi e distribuzione per attivita.

### Verifica locale

- `flutter test test/state_management/cubits/trip_track_cubit_test.dart test/ui/pages/trip_diary_presenter_test.dart`
- `flutter analyze`
- `flutter test`

### Blocked by

- Issue 3.

---

## Issue 5 - Profilo salva la Preferenza Privacy globale

**Tipo:** feature · **Area:** backend + mobile · **Dipendenze:** nessuna

**Stato locale:** implementata. Verifica mobile passata; test backend scritti
ma non eseguibili in locale finche Postgres `localhost:5432` non e attivo.

**User stories covered:** 25, 26, 27, 28, 29, 30, 31, 32, 38, 39, 40

### What to build

Aggiungere una sezione Profilo/Impostazioni raggiungibile dal drawer laterale.
La pagina mostra nome, email, logout e un selettore di Preferenza Privacy
globale.

Il backend salva la Preferenza Privacy in un modello dedicato one-to-one con
l'utente autenticato ed espone endpoint dedicati per leggerla e aggiornarla.
Questa issue non applica ancora la privacy a mappe, diario o export.

### Acceptance criteria

- [x] Il backend persiste una Preferenza Privacy globale per utente con default
      `precise`.
- [x] Il backend espone `GET /api/privacy/settings` autenticato.
- [x] Il backend espone `PUT /api/privacy/settings` autenticato.
- [x] I Livelli Privacy ammessi sono `precise`, `approximate`, `aggregated`.
- [x] Valori privacy invalidi sono rifiutati con errore 4xx.
- [x] Le impostazioni sono isolate per utente.
- [x] Il drawer laterale espone una voce Profilo.
- [x] La pagina Profilo mostra nome/email dell'utente autenticato.
- [x] La pagina Profilo permette di selezionare Precisa, Approssimata,
      Aggregata e salva la scelta sul backend.
- [x] La pagina Profilo mostra stati loading, saving ed errore.
- [x] La pagina Profilo contiene il logout.
- [x] Test backend coprono default, lettura, update, valore invalido e user
      isolation.
- [x] Test mobile coprono loading, saving, errore e selezione privacy.

### Verifica locale

- `flutter test test/state_management/cubits/privacy_settings_cubit/privacy_settings_cubit_test.dart test/state_management/cubits/trip_track_cubit_test.dart`
- `flutter analyze`
- `flutter test`
- `../.venv/bin/python -m py_compile accounts/models.py accounts/privacy_api.py accounts/schemas.py accounts/admin.py accounts/tests/test_privacy_settings_api.py config/urls.py`
- `../.venv/bin/pytest accounts/tests/test_privacy_settings_api.py` non
  completato: Postgres locale rifiuta connessioni su `localhost:5432`.

### Blocked by

None - can start immediately.

---

## Issue 6 - Dettaglio Viaggio usa un unico state owner per Mappa, Diario e Statistiche

**Tipo:** refactor/feature hardening · **Area:** mobile · **Dipendenze:** Issue 1, Issue 2, Issue 3, Issue 4

**Stato locale:** implementata. Il `TripDetailPage` monta un solo
`TripTrackCubit`, condiviso da Mappa, Diario e Statistiche; i test coprono
transizione pending/enriched, retry e chiusura dello stream.

**User stories covered:** 7, 9, 16, 24, 33, 34, 35

### What to build

Consolidare lo stato del Dettaglio Viaggio in un unico state owner mobile che
coordina Mappa, Diario, Statistiche, read model, Traiettoria del Viaggio base e
stream SSE.

Questa issue serve a chiudere l'integrazione dopo le slice funzionali: evita
fetch duplicati incoerenti, rende chiaro quando si apre/chiude lo stream e
garantisce che tutte le tab vedano lo stesso stato del Viaggio.

### Acceptance criteria

- [x] Un unico state owner del Dettaglio Viaggio carica diary read model e track
      base quando necessari.
- [x] Mappa, Diario e Statistiche leggono dallo stesso stato coerente.
- [x] Il Dettaglio Viaggio non duplica fetch non necessari tra tab.
- [x] Il Dettaglio Viaggio apre lo stream SSE solo nello stato pending e lo
      chiude al dispose o quando il diario diventa arricchito.
- [x] La transizione pending -> enriched aggiorna insieme Mappa, Diario e
      Statistiche.
- [x] Errori rete, stream chiuso e retry manuale sono rappresentati senza perdere
      la Traiettoria del Viaggio base quando disponibile.
- [x] Test mobile coprono transizione base/pending/enriched, retry, chiusura
      stream e coerenza tra tab.

### Verifica locale

- `flutter test test/state_management/cubits/privacy_settings_cubit/privacy_settings_cubit_test.dart test/state_management/cubits/trip_track_cubit_test.dart`
- `flutter analyze`
- `flutter test`

### Blocked by

- Issue 1.
- Issue 2.
- Issue 3.
- Issue 4.
