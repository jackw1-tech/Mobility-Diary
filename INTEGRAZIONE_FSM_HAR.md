# Integrazione FSM Mobile e HAR

## Obiettivo

L'app mobile oggi usa una FSM per decidere se l'utente è fermo, in possibile movimento
o in tracking attivo. Il progetto HAR, invece, contiene modelli di Human Activity
Recognition per classificare il tipo di attività svolta a partire da finestre di
sensori inerziali.

L'integrazione corretta non è sostituire la FSM con HAR, ma farli collaborare:

```text
FSM = decide se acquisire, risparmiare batteria, aprire o chiudere tracking
HAR = decide che attività sta avvenendo dentro una finestra sensore
```

## Stato Attuale Dell'App Mobile

La FSM dell'app distingue tre stati principali:

```text
STATIONARY
POTENTIAL_MOTION
ACTIVE_TRACKING
```

Questi stati rispondono alla domanda:

```text
Devo tracciare o no?
```

La FSM usa soprattutto:

- sigma dell'accelerometro;
- velocità GPS;
- finestre consecutive di movimento o quiete;
- timeout;
- periodo di grazia prima di tornare fermo.

Lo stato `ACTIVE_TRACKING` significa che il tracking è confermato, ma non dice ancora
se l'utente stia camminando, correndo, andando in bici o viaggiando su un veicolo.

## Stato Attuale Di HAR

Il progetto HAR classifica finestre sensore in cinque classi:

```text
IDLE
WALKING
RUNNING
BIKING
MOVING_VEHICLE
```

Queste classi rispondono alla domanda:

```text
Che attività sto facendo mentre traccio?
```

Il modello migliore presente in `HAR/` usa:

- finestre da 5 secondi;
- 500 campioni per finestra;
- frequenza attesa di circa 100 Hz;
- 9 canali:
  - Acc_x, Acc_y, Acc_z;
  - Gyr_x, Gyr_y, Gyr_z;
  - Mag_x, Mag_y, Mag_z;
- normalizzazione per canale con media e deviazione standard salvate in
  `HAR/processed_9ch/shl_9ch_5class_norm_stats.json`.

Il modello migliore complessivo è CNN + GRU bidirezionale, ma la GRU usa contesto
temporale lungo e anche futuro. Per questo è più adatta a correggere il diario a
posteriori che a prendere decisioni live immediate.

## Differenza Concettuale

FSM e HAR non rappresentano lo stesso livello.

```text
FSM: stato operativo del tracking
HAR: etichetta semantica dell'attività
```

Esempi:

```text
FSM ACTIVE_TRACKING + HAR WALKING = viaggio a piedi
FSM ACTIVE_TRACKING + HAR BIKING = viaggio in bici
FSM ACTIVE_TRACKING + HAR MOVING_VEHICLE = viaggio su mezzo o auto
FSM ACTIVE_TRACKING + HAR IDLE = pausa dentro un viaggio, non fine immediata
```

La classe HAR `IDLE` non deve chiudere automaticamente il tracking, perché può
rappresentare anche un mezzo fermo al semaforo, in stazione o nel traffico.

## Architettura Consigliata

```text
Sensori mobile
   ↓
Buffer finestre 5s
   ↓
Metriche leggere: sigma, velocità GPS
   ↓
FSM
   ↓
se serve: HAR classifier
   ↓
attività stimata + stato tracking
   ↓
SQLite / diario
```

La FSM decide quando HAR deve lavorare. HAR produce evidenza aggiuntiva e arricchisce
il diario con il tipo di attività.

## Comportamento Per Stato

### STATIONARY

In questo stato l'app deve consumare poco.

Comportamento consigliato:

- accelerometro leggero;
- GPS spento;
- HAR spento o eseguito molto raramente;
- se la sigma supera la soglia per più finestre consecutive, passaggio a
  `POTENTIAL_MOTION`.

### POTENTIAL_MOTION

Questo è lo stato in cui l'app sta verificando se il movimento è reale.

Comportamento consigliato:

- accendere sensori completi;
- raccogliere finestre compatibili con HAR;
- dare priorita al GPS per confermare o smentire il viaggio;
- usare HAR e sensori inerziali come contesto/fallback, non come decisori primari;
- se il GPS affidabile supera la soglia, passare a `ACTIVE_TRACKING`;
- se il GPS affidabile indica fermo per piu fix, tornare a `STATIONARY`;
- usare movimento sostenuto solo quando il GPS e assente o poco affidabile.

Classi HAR che possono confermare movimento:

```text
WALKING
RUNNING
BIKING
MOVING_VEHICLE
```

### ACTIVE_TRACKING

In questo stato il viaggio è confermato.

Comportamento consigliato:

- eseguire HAR ogni finestra da 5 secondi;
- salvare l'attività stimata;
- salvare confidenza e probabilità se disponibili;
- continuare a usare GPS e sigma per capire se il viaggio è terminato;
- non chiudere il tracking solo perché HAR dice `IDLE`.

Per tornare a `STATIONARY` servono ancora prove robuste:

```text
GPS basso + sigma bassa + tempo di grazia
```

## Mappatura Operativa HAR → FSM

```text
HAR IDLE
  → prova di possibile fermata
  → non basta da sola per chiudere il tracking

HAR WALKING
  → movimento umano confermato
  → attività del diario: camminata

HAR RUNNING
  → movimento umano confermato
  → attività del diario: corsa

HAR BIKING
  → movimento confermato
  → attività del diario: bici

HAR MOVING_VEHICLE
  → movimento confermato
  → attività del diario: veicolo o trasporto motorizzato
```

## Stato Attuale Dell'App Mobile

Oggi l'app:

- calcola soprattutto la sigma dall'accelerometro;
- usa accelerometro a 10 Hz in `STATIONARY`;
- usa accelerometro, giroscopio e magnetometro a 100 Hz in `POTENTIAL_MOTION` e `ACTIVE_TRACKING`;
- costruisce finestre HAR da 5 secondi in RAM;
- espone una matrice normalizzata `500 x 9` per il modello;
- mantiene anche la matrice grezza per debug e controllo qualita;
- salva le finestre HAR in SQLite quando il tracking e confermato;
- non integra ancora un runtime ML;
- non chiama ancora FastAPI;
- non contiene modelli `.tflite`.

Il progetto HAR contiene modelli `.keras`, quindi serve un passaggio di conversione
prima dell'uso on-device in Flutter.

## Due Strategie Possibili

### Strategia Scelta: Adattare L'App Al Modello HAR

L'app raccoglie dati nel formato atteso dal modello già allenato:

```text
100 Hz
5 secondi
500 campioni
9 canali
```

Vantaggi:

- permette di riusare direttamente il modello HAR esistente;
- meno lavoro lato training.

Svantaggi:

- maggiore consumo batteria;
- più complessità nel runtime sensori;
- il sistema operativo puo introdurre jitter, quindi serve normalizzazione a 500 righe;
- possibile mismatch tra dati SHL e dati reali dell'app.

### Alternativa Scartata Per Ora: Adattare HAR All'App Mobile

Si riallena o adatta HAR sul formato realmente sostenibile per l'app:

```text
50 Hz
5 secondi
250 campioni
6 o 9 canali
```

Vantaggi:

- più realistico per produzione mobile;
- migliore coerenza tra modello e runtime reale;
- minore consumo rispetto ai 100 Hz.

Svantaggi:

- richiede nuovo preprocessing;
- richiede nuovo training;
- bisogna rivalutare metriche e accuratezza.

Per una app mobile robusta, la seconda strategia è probabilmente la più sana.

## Architettura A Tre Livelli

La scelta consigliata è usare tre livelli di classificazione, ognuno con un ruolo
diverso:

```text
1. Adesso:
   CNN live, provvisoria

2. Ultimi 30-60 secondi:
   CNN + smoothing temporale, più stabile

3. Fine viaggio:
   GRU, definitiva
```

Questi tre livelli non devono sostituire la FSM. Devono produrre label di attività
con diversi gradi di affidabilità.

```text
FSM = ciclo di vita del tracking
CNN = attività live provvisoria
Smoothing = attività live stabilizzata
GRU = attività finale del diario
```

## Dati Necessari

Per far funzionare bene i tre livelli servono dati raccolti a finestre.

Ogni finestra HAR deve avere:

```text
sessionId
startTimestamp
endTimestamp
sensorMatrix
samplingHz
channels
gpsSpeedMps opzionale
gpsAccuracyMeters opzionale
```

Nel formato del modello HAR attuale, `sensorMatrix` è:

```text
500 righe x 9 canali
5 secondi
circa 100 Hz
Acc_x, Acc_y, Acc_z
Gyr_x, Gyr_y, Gyr_z
Mag_x, Mag_y, Mag_z
```

Se si decide di adattare HAR all'app mobile, il formato può diventare:

```text
250 righe x 6/9 canali
5 secondi
circa 50 Hz
```

In quel caso il modello va riallenato sul nuovo formato.

Oltre alla finestra sensore, conviene salvare anche gli output dei tre livelli:

```text
cnnLabel
cnnConfidence
cnnProbabilities

smoothedLabel
smoothedConfidence opzionale
smoothedWindowSize

gruLabel
gruConfidence
gruProbabilities opzionale

isFinalized
```

Se possibile, conviene salvare anche l'embedding CNN, cioè il vettore intermedio
prodotto dalla CNN prima della classificazione finale:

```text
cnnEmbedding = vettore di 128 numeri
```

Questo è utile perché la GRU del progetto HAR non legge direttamente le label CNN.
Legge sequenze di embedding prodotti dalla CNN.

## Livello 1: CNN Live Provvisoria

La CNN lavora su una finestra singola da 5 secondi.

Flusso:

```text
sensori 5s
   ↓
finestra normalizzata
   ↓
CNN
   ↓
label + probabilità
```

Esempio:

```text
12:00:00 - 12:00:05 → WALKING 0.82
12:00:05 - 12:00:10 → WALKING 0.76
12:00:10 - 12:00:15 → IDLE 0.51
```

Questa label serve per:

- mostrare subito una stima nella UI;
- dare evidenza aggiuntiva alla FSM;
- salvare una prima classificazione della finestra;
- alimentare lo smoothing;
- produrre embedding per la GRU finale.

La CNN è veloce e adatta al live, ma può sbagliare su finestre isolate. Il caso più
importante è `IDLE` dentro un viaggio su veicolo fermo.

Regola:

```text
cnnLabel = IDLE non chiude mai da sola il viaggio.
```

## Livello 2: CNN + Smoothing Temporale

Lo smoothing temporale stabilizza le predizioni CNN guardando una piccola sequenza di
finestre vicine.

Esempio senza smoothing:

```text
MOVING_VEHICLE
MOVING_VEHICLE
IDLE
MOVING_VEHICLE
MOVING_VEHICLE
```

Esempio con smoothing:

```text
MOVING_VEHICLE
MOVING_VEHICLE
MOVING_VEHICLE
MOVING_VEHICLE
MOVING_VEHICLE
```

Per il live conviene usare uno smoothing corto, per esempio:

```text
5 finestre  = 25 secondi
9 finestre  = 45 secondi
13 finestre = 65 secondi
```

Il modo più semplice è un voto di maggioranza sulle ultime finestre:

```text
ultime N label CNN → label più frequente → smoothedLabel
```

Questo è uno smoothing causale, perché usa solo il passato e il presente.

Pro:

- funziona live;
- è semplice;
- riduce errori isolati;
- rende la UI meno nervosa;
- costa poco in CPU e batteria.

Contro:

- reagisce con un po' di ritardo ai cambi attività;
- se N è troppo grande, cancella attività brevi;
- è meno preciso dello smoothing centrato offline e della GRU.

Esempio di ritardo:

```text
WALKING → WALKING → WALKING → BIKING → BIKING
```

Con una finestra di smoothing troppo lunga, l'app può continuare a mostrare
`WALKING` per qualche finestra anche se l'utente è passato a `BIKING`.

Regola pratica:

```text
N piccolo = più reattivo, meno stabile
N grande = più stabile, meno reattivo
```

Per iniziare, una finestra di 9 predizioni è un buon compromesso:

```text
9 x 5 secondi = 45 secondi
```

Nell'app lo smoothing dovrebbe produrre una label più stabile, ma ancora non
definitiva:

```text
cnnLabel = attività immediata
smoothedLabel = attività live stabilizzata
```

## Livello 3: GRU A Fine Viaggio

La GRU bidirezionale presente in HAR usa sequenze di 64 finestre:

```text
64 finestre x 5 secondi = 320 secondi
```

Quindi usa circa 5 minuti e 20 secondi di contesto.

Essendo bidirezionale, guarda sia il passato sia il futuro rispetto alla finestra che
sta correggendo. Per questo è molto adatta al post-processing, ma non al live
immediato.

Nel disegno scelto qui, la GRU viene eseguita a fine viaggio:

```text
utente preme Stop
oppure FSM chiude la sessione
   ↓
recupero finestre della sessione
   ↓
recupero/calcolo embedding CNN
   ↓
GRU
   ↓
scrivo label finali nel diario
```

La GRU può correggere errori che la CNN live non può capire da sola.

Esempio live:

```text
MOVING_VEHICLE
MOVING_VEHICLE
IDLE
IDLE
MOVING_VEHICLE
MOVING_VEHICLE
```

Esempio dopo GRU:

```text
MOVING_VEHICLE
MOVING_VEHICLE
MOVING_VEHICLE
MOVING_VEHICLE
MOVING_VEHICLE
MOVING_VEHICLE
```

La GRU può farlo perché vede che gli `IDLE` erano in mezzo a un contesto da veicolo,
quindi probabilmente erano semaforo, traffico o fermata.

Output consigliato:

```text
gruLabel = label finale
isFinalized = true
```

Dopo la GRU, il diario può mostrare la classificazione finale invece di quella live.

### Bordo Finale, Coda Breve E Fallback

Anche quando la GRU gira a fine viaggio, esiste un problema di bordo finale.

La GRU bidirezionale corregge meglio una finestra quando può vedere sia cosa è successo
prima sia cosa è successo dopo. Su una sessione da 10 minuti, una finestra verso
`9:50` ha molto passato ma poco futuro, perché il viaggio finisce quasi subito dopo.

Esempio:

```text
0:00 ------------------------------ 10:00
        contesto buono        bordo finale più debole
```

Questo non significa che la GRU sia inutilizzabile sulle ultime finestre, ma significa
che quelle predizioni sono meno forti rispetto alle finestre centrali.

La regola consigliata è:

```text
GRU a fine viaggio
+
coda breve 30-60s se possibile
+
fallback a smoothedLabel sulle ultime finestre
```

La coda breve consiste nel continuare a raccogliere sensori per poco tempo dopo che la
FSM ha deciso la fine del viaggio o dopo che l'utente ha premuto Stop.

Esempio:

```text
viaggio rilevato: 0:00 - 10:00
coda sensori:     10:00 - 10:45
```

Questa coda non deve necessariamente diventare parte del viaggio nel diario. Serve
soprattutto a dare alla GRU un po' di "futuro" per correggere meglio le finestre
finali del viaggio.

Perché aiuta:

```text
senza coda:
  finestra 9:50 vede poco futuro

con coda:
  finestra 9:50 vede anche cosa succede dopo la chiusura
```

Se dopo il viaggio l'utente resta davvero fermo, la coda conferma che la parte finale
stava andando verso `IDLE`. Se invece la chiusura era incerta o troppo precoce, la coda
può aiutare a non correggere male gli ultimi secondi.

Il fallback serve quando non c'è abbastanza contesto futuro, oppure quando non si vuole
tenere accesi i sensori dopo la fine.

Regola operativa:

```text
se la finestra ha abbastanza contesto passato/futuro:
  activityFinal = gruLabel
else:
  activityFinal = smoothedLabel
```

Un criterio semplice può essere:

```text
prime 30-60s della sessione:
  usare GRU se disponibile, altrimenti smoothedLabel

parte centrale:
  usare gruLabel

ultime 30-60s senza coda:
  preferire smoothedLabel o marcare gruLabel come meno affidabile

ultime 30-60s con coda:
  usare gruLabel se la coda fornisce contesto sufficiente
```

Questa soluzione evita di trattare la GRU come una verità assoluta nei punti in cui ha
meno informazione, mantenendo comunque il vantaggio principale della GRU sulla parte
centrale e più lunga del viaggio.

## Quando Usare Ogni Livello

Durante il viaggio:

```text
ogni 5 secondi:
  genera finestra sensore
  esegui CNN
  salva cnnLabel
  aggiorna smoothing
  salva smoothedLabel
  mostra in UI label provvisoria/stabilizzata
```

A fine viaggio:

```text
opzionale: raccogli coda breve 30-60s
carica tutte le finestre della sessione + coda
calcola o carica embedding CNN
esegui GRU
salva gruLabel per ogni finestra con contesto sufficiente
usa smoothedLabel come fallback sui bordi poco affidabili
marca la sessione come finalizzata
```

La UI può distinguere chiaramente:

```text
Durante il viaggio:
  attività corrente = smoothedLabel
  dettaglio tecnico = cnnLabel provvisoria

Dopo fine viaggio:
  attività finale = gruLabel
```

## Tabella Riassuntiva

```text
Livello      Quando gira        Input principale       Output             Uso
CNN          ogni 5s live        finestra sensori       cnnLabel           immediato
Smoothing    ogni 5s live        ultime label CNN       smoothedLabel      stabile
GRU          fine viaggio        sequenza embedding     gruLabel           definitivo
```

## Rapporto Con La FSM

La FSM continua a decidere lo stato operativo:

```text
STATIONARY
POTENTIAL_MOTION
ACTIVE_TRACKING
```

HAR produce label di attività:

```text
cnnLabel
smoothedLabel
gruLabel
```

La FSM può usare CNN e smoothing come evidenza durante il live, ma non deve aspettare
la GRU per decidere se il viaggio è attivo.

Regole consigliate:

```text
POTENTIAL_MOTION + CNN/SMOOTHED WALKING/RUNNING/BIKING/MOVING_VEHICLE
  → aumenta confidenza di movimento
  → non basta se il GPS affidabile indica fermo

ACTIVE_TRACKING + CNN/SMOOTHED IDLE
  → possibile pausa
  → non chiudere senza GPS basso + sigma bassa + tempo di grazia

Fine viaggio + GRU
  → corregge solo il diario
  → non riscrive retroattivamente la logica live della FSM
```

## Piano Di Integrazione

1. Aggiungere un evento dominio per HAR, ad esempio `HarWindowClassified`.
2. Estendere lo snapshot con:
   - `latestCnnActivity`;
   - `latestSmoothedActivity`;
   - `latestActivityConfidence`;
   - `activityProbabilities`;
   - `isActivityFinalized`.
3. Aggiungere buffer sensori da 5 secondi nel runtime mobile.
4. Raccogliere realmente accelerometro, giroscopio e magnetometro.
5. Normalizzare le finestre con le statistiche del modello HAR.
6. Convertire il modello CNN 9 canali da `.keras` a `.tflite`.
7. Integrare un servizio Flutter, ad esempio `HarClassifier`.
8. Salvare per ogni finestra `cnnLabel`, probabilità e, se possibile, embedding CNN.
9. Implementare smoothing causale breve sulle ultime predizioni CNN.
10. Salvare `smoothedLabel` in SQLite e usarla come attività live stabilizzata.
11. Fare usare CNN/smoothing alla FSM come evidenza, non come unico decisore.
12. A fine viaggio eseguire la GRU sulla sequenza di embedding della sessione.
13. Salvare `gruLabel` e marcare le finestre come finalizzate.

## Schema Finale

```text
                         LIVE

                 ┌──────────────────┐
                 │ Sensori Mobile    │
                 └────────┬─────────┘
                          │
                          ▼
                 ┌──────────────────┐
                 │ Buffer 5 secondi  │
                 └────────┬─────────┘
                          │
             ┌────────────┴────────────┐
             ▼                         ▼
    ┌─────────────────┐       ┌─────────────────┐
    │ Sigma + GPS      │       │ CNN HAR          │
    └────────┬────────┘       └────────┬────────┘
             │                         │
             │                         ▼
             │                ┌─────────────────┐
             │                │ Smoothing live   │
             │                └────────┬────────┘
             │                         │
             └────────────┬────────────┘
                          ▼
                  ┌──────────────┐
                  │ FSM Tracking  │
                  └──────┬───────┘
                         ▼
                  ┌──────────────┐
                  │ Diario SQLite │
                  │ cnn/smoothed  │
                  └──────┬───────┘
                         │
                         ▼
                    FINE VIAGGIO
                         │
                         ▼
                  ┌──────────────┐
                  │ GRU finale    │
                  └──────┬───────┘
                         ▼
                  ┌──────────────┐
                  │ Diario finale │
                  │ gruLabel      │
                  └──────────────┘
```

## Regola Di Progetto

La FSM deve restare responsabile del ciclo di vita del tracking:

```text
start sessione
conferma movimento
mantieni tracking
chiudi sessione
```

HAR deve arricchire il diario:

```text
camminata
corsa
bici
veicolo
idle dentro una sessione
```

In sintesi:

```text
FSM decide quando tracciare.
HAR decide cosa sta succedendo mentre si traccia.
```

## Aggiornamento: Potential Motion E GPS In Stationary

La strategia piu sensata e questa:

```text
STATIONARY
  accelerometro leggero
  GPS lento
  niente finestre HAR
  scrittura rada dei punti GPS per riconoscere soste

POTENTIAL_MOTION
  accelerometro + giroscopio + magnetometro
  costruzione finestre HAR da 5 secondi in RAM
  niente chiamata al modello HAR
  niente scrittura SQLite dei sensori

ACTIVE_TRACKING
  GPS rapido
  finestre HAR disponibili
  finestre HAR salvate in SQLite
  dati disponibili per diario e classificazione finale
```

### Perche Costruire Finestre HAR Gia In Potential Motion

Conviene farlo, ma solo in memoria.

Il motivo e che `POTENTIAL_MOTION` e proprio la fase in cui l'app ha visto un
segnale sospetto ma non ha ancora deciso che il viaggio e reale. Se aspettiamo
`ACTIVE_TRACKING`, rischiamo di perdere i primi 5-10 secondi del movimento.

Quindi l'app puo iniziare a costruire finestre da 5 secondi con:

```text
Acc_x, Acc_y, Acc_z
Gyr_x, Gyr_y, Gyr_z
Mag_x, Mag_y, Mag_z
```

Queste finestre non interrogano HAR e non vengono mandate a FastAPI. Sono solo
buffer temporanei. Se la FSM torna a `STATIONARY`, si possono scartare. Se la FSM
passa ad `ACTIVE_TRACKING`, quelle finestre diventano contesto utile per la CNN,
lo smoothing o la GRU finale.

### Problema Degli Hz Diversi

Non bisogna assumere che tutti i sensori abbiano sempre la stessa frequenza.
Per questo la finestra HAR deve portarsi dietro anche i metadati:

```text
accelerometerHz
gyroscopeHz
magnetometerHz
startedAt
endedAt
sampleCount
channelNames
matrix
```

Il frontend prepara gia una matrice per il modello:

```text
modelInputMatrix
  500 righe
  9 canali
  circa 100 Hz
```

La matrice grezza resta comunque disponibile:

```text
matrix
  righe reali ricevute dal dispositivo
  9 canali
  utile per debug e qualita del segnale
```

Nel nostro caso, per ridurre ambiguita, `POTENTIAL_MOTION` accende gia
accelerometro, giroscopio e magnetometro a 100 Hz. Cosi le finestre sono
allineate al formato HAR `500 x 9`.

### Perche Usare GPS Anche In Stationary

`STATIONARY` non significa "non mi interessa dove sono". Significa "non sto
facendo un viaggio".

Se il telefono resta tre ore sul tavolo in palestra, a livello macro l'utente e
fermo, ma il diario deve comunque poter dire:

```text
sono stato in palestra dalle 15:00 alle 18:00
```

Per questo in `STATIONARY` ha senso tenere un GPS lento e low-power:

```text
gpsEnabled = true
gpsInterval = 3 minuti
gpsAccuracy = lowPower
gpsDistanceFilterMeters = 100
persistGpsPoints = true
```

Questo GPS non serve a disegnare una rotta. Serve a mantenere un'evidenza di
presenza in un luogo significativo. La rotta resta una responsabilita di
`ACTIVE_TRACKING`, dove il GPS diventa piu frequente e i punti rappresentano il
percorso.

### Decisione Architetturale

Il gioco vale la candela cosi:

```text
Costruire HAR in POTENTIAL_MOTION
  si, per non perdere i primi secondi sospetti

Interrogare HAR in POTENTIAL_MOTION
  no, perche la FSM deve ancora confermare se il viaggio esiste

Usare HAR in STATIONARY
  no, costa troppo rispetto al valore informativo

Usare GPS lento in STATIONARY
  si, per riconoscere soste lunghe e luoghi visitati
```

In altre parole:

```text
STATIONARY capisce dove sei rimasto.
POTENTIAL_MOTION prepara dati, ma non decide con HAR.
ACTIVE_TRACKING classifica e salva il viaggio.
```
