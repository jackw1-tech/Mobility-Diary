# Report Frontend Attuale

Questo report descrive lo stato attuale dell'app mobile Flutter dopo
l'allineamento delle finestre HAR al formato `500 x 9` a 100 Hz.

## Sintesi

L'app mobile oggi non fa ancora classificazione HAR vera e propria. Non chiama
FastAPI, non esegue CNN/GRU e non decide il tipo di attivita.

Quello che fa oggi e:

- mostrare lo stato del tracking nella schermata principale;
- accendere/spegnere sensori diversi in base allo stato FSM;
- calcolare `sigma` dall'accelerometro per capire se c'e movimento;
- usare GPS per confermare movimento o rilevare una sosta;
- creare sessioni, transizioni e punti GPS in SQLite;
- costruire finestre HAR da 5 secondi in RAM quando serve;
- preparare una matrice modello `500 x 9` a 100 Hz.

## Schermata Principale

La pagina principale e `HomePage`.

L'utente vede:

- stato corrente: `STATIONARY`, `POTENTIAL_MOTION` o `ACTIVE_TRACKING`;
- pulsante `Start` / `Stop`;
- valore live di `sigma`;
- velocita GPS in km/h;
- lista dei sensori attivi;
- ultima transizione FSM;
- lista dei valori live aggregati per secondo.

La schermata non mostra ancora:

- label HAR tipo walking, biking, vehicle, idle;
- diario finale delle soste;
- rotta su mappa;
- output CNN/GRU;
- stato FastAPI.

## Flusso Generale

Il flusso attuale e:

```text
HomePage
  legge AcquisitionCubitState
    legge AcquisitionSnapshot
      prodotto da AcquisitionRepositoryImpl
        aggiorna AcquisitionFsm
        ascolta AcquisitionSensorRuntime
        scrive parte dei dati in SQLite
```

Quando l'utente preme `Start`:

```text
HomePage
  -> AcquisitionCubit.startTracking()
    -> AcquisitionRepositoryImpl.startTracking()
      -> crea sessione SQLite
      -> crea snapshot STATIONARY
      -> avvia AcquisitionSensorRuntime con SamplingProfile.stationary()
```

Quando l'utente preme `Stop`:

```text
HomePage
  -> AcquisitionCubit.stopTracking()
    -> AcquisitionRepositoryImpl.stopTracking()
      -> ferma runtime sensori
      -> chiude sessione SQLite
      -> torna a snapshot idle
```

## Strutture Dati Principali

### AcquisitionSnapshot

`AcquisitionSnapshot` e la fotografia corrente dello stato dell'app.

Contiene:

```text
isTracking
trackingState
samplingProfile
latestSigma
latestSpeedMetersPerSecond
lastTransition
updatedAt
```

E il dato principale che arriva al frontend. La UI non legge direttamente i
sensori: legge questo snapshot.

### AcquisitionCubitState

`AcquisitionCubitState` incapsula lo snapshot per la UI.

Contiene:

```text
status
snapshot
metricClusters
```

`status` puo essere:

```text
idle
tracking
```

`metricClusters` raggruppa i valori live in blocchi da circa 1 secondo. Ogni
cluster contiene media, minimo e massimo di sigma e velocita.

### SamplingProfile

`SamplingProfile` dice al runtime quali sensori usare e come usarli.

Contiene:

```text
accelerometerHz
gyroscopeHz
magnetometerHz
gpsEnabled
gpsInterval
gpsDistanceFilterMeters
gpsAccuracy
harWindowEnabled
persistSensorWindows
persistGpsPoints
```

Questa struttura e fondamentale: e il ponte tra la FSM e i sensori reali.

### TrackingEvent

La FSM non riceve sensori grezzi. Riceve eventi gia sintetizzati:

```text
MotionWindowEvaluated
  timestamp
  sigma
  sampleCount

GpsFixReceived
  timestamp
  latitude
  longitude
  speedMetersPerSecond
  accuracyMeters

PotentialMotionTimeoutElapsed
  timestamp
```

### HarSensorSample

Un campione HAR contiene 9 canali:

```text
timestamp
accX, accY, accZ
gyrX, gyrY, gyrZ
magX, magY, magZ
```

L'ordine dei canali e:

```text
Acc_x, Acc_y, Acc_z,
Gyr_x, Gyr_y, Gyr_z,
Mag_x, Mag_y, Mag_z
```

### HarSensorWindow

Una finestra HAR e un blocco temporale di circa 5 secondi.

Contiene:

```text
startedAt
endedAt
accelerometerHz
gyroscopeHz
magnetometerHz
samples
```

Espone due forme dati:

```text
matrix
  matrice grezza
  numero righe = campioni realmente arrivati dal telefono
  colonne = 9

modelInputMatrix
  matrice normalizzata
  righe = 500
  colonne = 9
  frequenza target = 100 Hz
```

Questo significa che il telefono conserva la verita grezza, ma prepara anche il
formato utile per il modello.

## Stato 0: Idle

`Idle` non e uno stato FSM vero separato. E il caso in cui `isTracking = false`.

In UI:

```text
stato mostrato: STATIONARY
testo: sensori fermi
pulsante: Start
sigma: 0
velocita: 0 km/h
sensori: non attivi
```

Struttura dati:

```text
AcquisitionSnapshot.idle()
  isTracking = false
  trackingState = STATIONARY
  samplingProfile = stationary
```

Nota importante: anche se lo snapshot contiene `SamplingProfile.stationary()`,
il runtime sensori e fermo perche `isTracking = false`.

## Stato 1: STATIONARY

`STATIONARY` significa: il tracking e acceso, ma l'app considera l'utente fermo
a livello macro.

Profilo attuale:

```text
accelerometerHz = 10
gyroscopeHz = 0
magnetometerHz = 0
gpsEnabled = true
gpsInterval = 3 minuti
gpsDistanceFilterMeters = 100
gpsAccuracy = lowPower
harWindowEnabled = false
persistSensorWindows = false
persistGpsPoints = true
```

Cosa fa il frontend/runtime:

- ascolta accelerometro a bassa frequenza;
- calcola finestre leggere di movimento;
- calcola `sigma`;
- ascolta GPS lento e low-power;
- salva pochi punti GPS per rilevare soste lunghe;
- non costruisce finestre HAR;
- non ascolta giroscopio;
- non ascolta magnetometro.

Perche GPS in stationary:

```text
telefono fermo sul tavolo in palestra
  -> sensori inerziali quasi fermi
  -> macro-stato STATIONARY
  -> GPS lento permette di dire: sei rimasto in palestra per ore
```

Transizione possibile:

```text
se sigma > soglia per 4 finestre consecutive
  STATIONARY -> POTENTIAL_MOTION
```

## Stato 2: POTENTIAL_MOTION

`POTENTIAL_MOTION` significa: l'app ha visto movimento sospetto, ma non ha ancora
confermato che esista un viaggio.

Profilo attuale:

```text
accelerometerHz = 100
gyroscopeHz = 100
magnetometerHz = 100
gpsEnabled = true
gpsInterval = 5 secondi
gpsDistanceFilterMeters = null
gpsAccuracy = highAccuracy
harWindowEnabled = true
persistSensorWindows = false
persistGpsPoints = false
```

Cosa fa:

- aumenta accelerometro a 100 Hz;
- accende giroscopio a 100 Hz;
- accende magnetometro a 100 Hz;
- accende GPS piu rapido;
- costruisce finestre HAR da 5 secondi in RAM;
- prepara `modelInputMatrix` `500 x 9`;
- non chiama ancora HAR;
- non manda nulla a FastAPI;
- non salva finestre sensori su SQLite;
- non salva punti GPS come rotta.

Perche costruire HAR qui:

```text
se aspetti ACTIVE_TRACKING
  perdi i primi secondi del movimento

se costruisci gia in POTENTIAL_MOTION
  puoi usare quei primi secondi dopo la conferma
```

Transizioni possibili:

```text
GPS affidabile e speed > 0.56 m/s circa
  POTENTIAL_MOTION -> ACTIVE_TRACKING

GPS affidabile e speed <= 0.1 m/s per 2 fix
  POTENTIAL_MOTION -> STATIONARY

movimento sostenuto per 8 finestre senza GPS affidabile
  POTENTIAL_MOTION -> ACTIVE_TRACKING

finestre ferme per 4 volte
  POTENTIAL_MOTION -> STATIONARY

timeout 60 secondi senza conferma
  POTENTIAL_MOTION -> STATIONARY
```

In questa fase il GPS pesa piu dell'inerziale:

```text
se il GPS affidabile dice fermo
  il movimento del telefono non basta a confermare il viaggio

se il GPS affidabile dice movimento
  il viaggio viene confermato subito

se il GPS manca o ha accuracy scarsa
  la FSM puo usare il movimento sostenuto come fallback
```

## Stato 3: ACTIVE_TRACKING

`ACTIVE_TRACKING` significa: il viaggio e confermato.

Profilo attuale:

```text
accelerometerHz = 100
gyroscopeHz = 100
magnetometerHz = 100
gpsEnabled = true
gpsInterval = 2 secondi
gpsDistanceFilterMeters = 3
gpsAccuracy = highAccuracy
harWindowEnabled = true
persistSensorWindows = true
persistGpsPoints = true
```

Cosa fa:

- continua a raccogliere sensori a 100 Hz;
- continua a costruire finestre HAR da 5 secondi;
- mantiene fino a 12 finestre HAR completate in RAM;
- prepara `modelInputMatrix` `500 x 9`;
- usa GPS rapido per tracciare il movimento;
- salva punti GPS su SQLite;
- salva transizioni FSM su SQLite.

Nota importante:

```text
GPS points
  salvati

state transitions
  salvate

HAR sensor windows
  costruite in RAM come cache live
  salvate in SQLite quando il tracking e confermato
  non ancora inviate a FastAPI
```

Quando `POTENTIAL_MOTION` diventa `ACTIVE_TRACKING`, il repository salva anche le
finestre HAR recenti che erano in RAM. Durante `ACTIVE_TRACKING`, ogni nuova
finestra completata viene salvata in `SensorWindows`. La RAM continua a tenere
solo le ultime 12 finestre per smoothing live, debug e retry leggero.

Ritorno a stationary:

```text
se velocita GPS <= 0.1 m/s
e sigma resta bassa
per almeno 2 minuti
  ACTIVE_TRACKING -> STATIONARY
```

## Persistenza SQLite

Il database locale contiene:

```text
AcquisitionSessions
  id
  deviceId
  startedAt
  endedAt

StateTransitions
  sessionId
  fromState
  toState
  reason
  timestamp
  sigma
  speedMps

GpsPoints
  sessionId
  latitude
  longitude
  timestamp
  speedMps
  accuracyMeters
  accepted
  rejectionReason
  isSynced

SensorWindows
  sessionId
  startTimestamp
  endTimestamp
  sampleCount
  frequencyHz
  matrixJson
  isSynced
```

Oggi `SensorWindows` viene popolata quando il viaggio e confermato. Le finestre
sono salvate nel formato normalizzato `500 x 9` tramite `matrixJson`.

## Contratto HAR Attuale

Il contratto dati per HAR ora e:

```text
targetSamplingHz = 100
targetDuration = 5 secondi
targetSampleCount = 500
channelCount = 9
shape = 500 x 9
```

Ogni riga della matrice e:

```text
[Acc_x, Acc_y, Acc_z, Gyr_x, Gyr_y, Gyr_z, Mag_x, Mag_y, Mag_z]
```

Il runtime aggiunge una riga HAR quando arriva un evento accelerometro. Per
giroscopio e magnetometro usa l'ultimo valore disponibile.

Questa scelta e pratica:

```text
accelerometro
  guida il clock della matrice

giroscopio/magnetometro
  vengono agganciati all'ultimo valore ricevuto
```

Se i campioni reali non sono esattamente 500, `modelInputMatrix` interpola la
sequenza grezza e restituisce comunque 500 righe.

## Cosa Manca Ancora

Manca ancora:

- chiamata FastAPI;
- payload JSON finale per HAR;
- inferenza CNN live;
- smoothing temporale delle label;
- GRU finale a fine viaggio;
- diario finale con soste, luoghi e mezzi;
- deduplicazione/clusterizzazione dei luoghi visitati;
- gestione robusta del background tracking.

## Lettura Architetturale

La divisione attuale e questa:

```text
FSM
  decide se siamo fermi, sospetti o in viaggio

SamplingProfile
  decide quali sensori accendere

Runtime sensori
  raccoglie accelerometro/GPS/gyro/mag
  produce eventi per la FSM
  costruisce finestre HAR

Repository
  coordina FSM, runtime e SQLite

Cubit
  espone snapshot e metriche alla UI

HomePage
  mostra lo stato corrente all'utente
```

In sintesi:

```text
STATIONARY
  capisce dove sei rimasto

POTENTIAL_MOTION
  prepara dati HAR ma non classifica

ACTIVE_TRACKING
  traccia il viaggio e prepara dati per classificazione
```
