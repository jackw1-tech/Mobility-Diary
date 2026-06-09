# Report Architettura: Elaborazione Live, Code e Tracking GPS

Questo report raccoglie le decisioni e i ragionamenti architetturali discussi
riguardo a come gestire, lato backend (FastAPI + PostGIS) e lato mobile
(Flutter), i dati prodotti durante `ACTIVE_TRACKING`: finestre sensori per la
classificazione HAR e punti GPS per la posizione live e il diario finale.

Le domande di partenza sono due:

```text
1. Per processare i dati che l'AI deve classificare,
   ha senso usare una coda o una chiamata diretta?

2. Come garantire GPS/velocita/stato in tempo reale
   senza far esplodere ne il telefono ne il backend?
```

## Contesto Architetturale Di Riferimento

Il design attuale (vedi `INTEGRAZIONE_FSM_HAR.md` e
`REPORT_FRONTEND_ATTUALE.md`) prevede che, durante `ACTIVE_TRACKING`, ogni 5
secondi:

```text
il telefono prepara una finestra sensori (matrice 500 x 9)
la manda al backend
il backend fa girare la CNN
il backend risponde con una label di attivita (es. WALKING 0.82)
```

Questo e un flusso continuo e frequente, non un job a fine viaggio: con N
utenti contemporaneamente attivi si hanno circa N/5 richieste al secondo
sostenute per tutta la durata dei viaggi.

## Parte 1: Coda O Chiamata Diretta Per La Classificazione HAR?

### Prima ipotesi: serve una risposta immediata

Se la label CNN deve apparire subito nella UI, il confronto e tra:

**Chiamata diretta (sincrona)**

```text
Pro:
  semplice da implementare e ragionare
  risposta immediata al client

Contro:
  il client resta bloccato sul tempo di elaborazione del server
  nessun controllo naturale sui picchi di carico
  difficile sfruttare bene GPU/CPU per l'inferenza ML
  un rallentamento del servizio di inferenza blocca anche l'ingestione
```

**Coda pura (asincrona end-to-end)**

```text
Pro:
  assorbe i picchi di carico
  permette di raggruppare piu richieste per un'inferenza piu efficiente
  resiliente: se il servizio AI si ferma, i dati restano in coda

Contro:
  aggiunge latenza proprio dove serve reattivita
  serve un canale di ritorno verso il client specifico
    (websocket, notifica push, polling)
  piu complessita operativa (broker, monitoraggio, dead-letter queue)
```

### Soluzione intermedia proposta (valida se serve risposta quasi immediata)

Il client fa una chiamata che **sembra** diretta e sincrona (manda la finestra,
aspetta, riceve la label), ma il server raggruppa le richieste arrivate quasi
nello stesso istante (es. entro 50-100 millisecondi) e le fa girare insieme
sulla CNN, in un unico passaggio sulla GPU. Questo si chiama comunemente
"dynamic batching" ed e gia disponibile in strumenti pronti all'uso (es.
NVIDIA Triton Inference Server, TensorFlow Serving, TorchServe): non va
costruito da zero.

```text
client -> POST finestra (sembra una normale chiamata sincrona)
              |
        server di inferenza con raggruppamento automatico
        (raccoglie le richieste vicine nel tempo, le processa insieme)
              |
        risposta individuale per ciascun client, latenza quasi invariata
```

Vantaggio: il client non cambia nulla nel suo modo di chiamare il server, ma
il server ottiene comunque l'efficienza del processamento a gruppi.

### Svolta: il delay e accettabile

Durante la discussione e emerso un punto chiave: dal vivo, oltre alla
posizione GPS, non c'e molto altro da mostrare in tempo reale stretto. La
label di attivita (`WALKING`, `BIKING`, ...) puo quindi arrivare con qualche
secondo di ritardo senza impattare l'esperienza utente.

Questo elimina il vincolo che rendeva necessaria la soluzione intermedia, e
**la coda asincrona pura diventa la scelta migliore senza compromessi**:

```text
1. il telefono manda la finestra al server
2. il server risponde subito "ricevuto" (non aspetta la CNN)
3. la finestra viene messa in una coda
4. un gruppo di worker pesca dalla coda quando puo,
   raggruppa piu finestre insieme e fa girare la CNN su tutte insieme
5. il risultato viene salvato
6. il telefono, quando aggiorna la UI, recupera l'ultima label disponibile
```

### Perche questa e la scelta giusta per il progetto

```text
massima robustezza sotto carico
  picchi di richieste vengono assorbiti dalla coda, nessun timeout
  per l'utente

massima efficienza dell'inferenza
  i worker possono raggruppare comodamente molte finestre
  prima di farle girare sul modello

resilienza
  se il servizio AI si ferma per manutenzione o crash,
  le finestre restano in coda e vengono processate al ritorno

architettura unica
  lo stesso schema (coda + worker) si usa sia per la
  classificazione live sia per l'elaborazione finale (GRU a fine viaggio)

coerenza con il design esistente
  lo schema SQLite ha gia campi isSynced su GpsPoints e SensorWindows:
  il sistema e gia pensato come "i dati arrivano e vengono
  processati quando possibile". La coda e l'estensione naturale
  di questa filosofia anche lato server
```

## Parte 2: GPS/Velocita/Stato In Tempo Reale Senza Sovraccaricare Nulla

### Lato telefono

Il design attuale (FSM + `SamplingProfile`) fa gia la cosa giusta: campiona il
GPS in modo adattivo in base allo stato (`lowPower` ogni 3 minuti in
`STATIONARY`, `highAccuracy` ogni 2 secondi con filtro 3 metri in
`ACTIVE_TRACKING`). Il principio e: non chiedere sempre il massimo, chiedi
solo quanto serve nel contesto.

Tecniche aggiuntive da sfruttare:

```text
gpsDistanceFilterMeters
  il sistema operativo emette un nuovo fix solo se ci si e spostati
  di una certa distanza: niente lavoro inutile quando si e fermi

mostrare la posizione live senza passare dal backend
  il dato GPS arriva direttamente dal sensore locale,
  il giro verso il server non serve a mostrarlo, solo a salvarlo

batch dei punti GPS prima dell'invio
  invece di una richiesta ogni 2 secondi, accumulare 30-60 secondi
  di punti e inviarli in un'unica richiesta: meno connessioni di
  rete aperte, che sono il vero costo per la batteria

compressione del payload (gzip)
  poche coordinate e timestamp si comprimono molto bene
```

### Lato rete

```text
evitare connessioni persistenti (websocket "always-on")
  solo per inviare punti GPS sporadici: il keepalive consuma
  batteria senza vantaggi reali se non serve risposta immediata

preferire poche richieste periodiche con piu dati dentro
  rispetto a tante richieste piccole e frequenti
```

### Lato backend (FastAPI + PostGIS)

```text
endpoint async + driver async (es. asyncpg)
  evita che il server si blocchi sotto carico concorrente

bulk insert invece di insert riga per riga
  ricevere un batch e scriverlo con una sola operazione
  (es. COPY o executemany), molto piu leggero per Postgres

disaccoppiare ricezione e scrittura pesante
  l'endpoint riceve il batch e lo mette in un buffer/coda interna;
  un processo separato scrive su PostGIS a intervalli regolari,
  raggruppando piu batch insieme

connection pooling (es. PgBouncer)
  con tanti utenti concorrenti, riusare le connessioni al DB
  invece di aprirne una per richiesta

partizionamento delle tabelle per tempo o per sessione
  se il volume cresce, per non far contendere scritture recenti
  e query storiche pesanti sulle stesse risorse
```

### Chi deve vedere cosa in tempo reale

```text
l'utente vede la propria posizione live
  non serve il backend: il dato e gia sul telefono.
  Il backend serve solo a persistere per il diario, non a mostrare

qualcun altro deve vedere quella posizione in tempo reale
  (dashboard, altro utente, operatore)
  li si che serve un meccanismo di push (websocket/SSE),
  ma mirato solo a chi ne ha bisogno, non un broadcast generale.
  Se questo caso non esiste oggi nel prodotto, non va costruito ora
```

## Parte 3: Pattern "Mostra In Locale, Persisti Sul Server" — Difficolta E Contro

Questo pattern non e difficile da realizzare: e gia quello che il progetto
implementa oggi. La UI (`HomePage`) legge `AcquisitionSnapshot`, prodotto
localmente da sensori e FSM, e non chiama mai il backend per mostrare
stato/velocita/sigma. Il backend entra in gioco solo per salvare e, in
seguito, classificare/correggere a posteriori.

I punti a cui prestare attenzione non sono ostacoli implementativi, ma
conseguenze del fatto che esistono due "versioni della verita":

```text
1. Disallineamento tra cio che si vede live e cio che finisce nel diario
   La label CNN live e provvisoria, la label GRU finale puo correggerla.
   L'utente potrebbe notare incongruenze tra "durante il viaggio" e
   "nel diario finale".
   -> Va comunicato chiaramente in UI: "stima live" vs "risultato finale"

2. Il telefono deve fidarsi dei propri calcoli
   Senza validazione server in tempo reale, la qualita di cio che si
   vede live dipende solo dai calcoli locali (filtri GPS, sigma, ecc.)
   -> Coerente con la scelta gia fatta: live = best effort,
      diario finale = verita

3. Robustezza della sincronizzazione differita
   Vanno gestiti bene i casi limite: app chiusa a meta sync,
   periodi lunghi offline, possibili duplicati, ordine dei dati
   -> Richiede test accurati sui casi limite, e il prezzo
      per avere un'esperienza live fluida e offline-first

4. Debug piu articolato
   Quando qualcosa sembra sbagliato, bisogna capire se il problema
   e nel calcolo locale, nella sincronizzazione o nell'elaborazione
   server, perche ci sono piu punti dove le cose possono divergere
```

L'alternativa — far dipendere la UI live da un giro verso il backend —
sarebbe piu complicata da costruire e piu fragile in produzione (latenza di
rete, gestione errori, stati di caricamento). Il pattern attuale evita tutto
questo: l'unica cosa da gestire con cura e la distinzione, resa chiara
all'utente, tra "stima live provvisoria" e "diario finale corretto".

## Sintesi Finale

```text
Classificazione HAR (ogni 5 secondi):
  coda + worker che raggruppano le finestre per un'inferenza efficiente
  risultato salvato e recuperato dal telefono quando aggiorna la UI
  (delay di pochi secondi accettabile, non impatta l'esperienza)

Persistenza ed elaborazione finale (GRU a fine viaggio):
  stesso schema coda + worker, gia naturale per un job non urgente

Posizione GPS live:
  mostrata sul telefono direttamente dal sensore locale,
  nessun giro verso il backend necessario per la visualizzazione

Invio dati al backend (HAR + GPS):
  batch periodici, non una richiesta per ogni singolo campione
  scrittura bulk e disaccoppiata su PostGIS

Principio guida comune:
  disaccoppiare la ricezione dal lavoro pesante,
  e mostrare i dati all'utente senza fargli fare
  il giro del server quando non serve
```
