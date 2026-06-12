# Report Macchina A Stati Attuale

Questo documento descrive il funzionamento attuale della macchina a stati del mobile, cioe il meccanismo che decide se l'utente e fermo, in movimento potenziale o in tracking attivo.

## Stati Visibili

L'app espone tre stati principali:

```text
STATIONARY
POTENTIAL_MOTION
ACTIVE_TRACKING
```

La UI continua a vedere un solo stato `STATIONARY`, ma internamente `STATIONARY` ha due profili di campionamento:

```text
STATIONARY recent
STATIONARY deep
```

Questi due profili non sono due stati UI diversi: servono solo a cambiare aggressivita del GPS.

## Profili Di Campionamento

### STATIONARY recent

Usato appena si entra in `STATIONARY` e per i primi 10 minuti.

```text
accelerometro: 10 Hz
giroscopio: 0 Hz
magnetometro: 0 Hz
GPS: attivo
GPS interval richiesto: 20 secondi
GPS distance filter: 30 metri
GPS accuracy: highAccuracy
HAR windows: disattivate
salvataggio sensor windows: no
salvataggio GPS points: si
```

Obiettivo: restare abbastanza reattivi se l'utente riparte poco dopo essersi fermato.

### STATIONARY deep

Usato dopo 10 minuti continuativi in `STATIONARY`.

```text
accelerometro: 10 Hz
giroscopio: 0 Hz
magnetometro: 0 Hz
GPS: attivo
GPS interval richiesto: 3 minuti
GPS distance filter: 100 metri
GPS accuracy: lowPower
HAR windows: disattivate
salvataggio sensor windows: no
salvataggio GPS points: si
```

Obiettivo: risparmiare batteria quando l'utente e davvero fermo a lungo, per esempio in palestra, casa, universita o ufficio.

### POTENTIAL_MOTION

```text
accelerometro: 100 Hz
giroscopio: 100 Hz
magnetometro: 100 Hz
GPS: attivo
GPS interval richiesto: 5 secondi
GPS distance filter: nessuno
GPS accuracy: highAccuracy
HAR windows: attive
salvataggio sensor windows: no
salvataggio GPS points: no
```

Obiettivo: capire se il movimento e reale oppure se e stato solo un falso positivo.

Le finestre HAR possono essere costruite in RAM, ma non vengono salvate come dati definitivi finche non si entra in `ACTIVE_TRACKING`.

### ACTIVE_TRACKING

```text
accelerometro: 100 Hz
giroscopio: 100 Hz
magnetometro: 100 Hz
GPS: attivo
GPS interval richiesto: 2 secondi
GPS distance filter: 3 metri
GPS accuracy: highAccuracy
HAR windows: attive
salvataggio sensor windows: si
salvataggio GPS points: si
```

Obiettivo: registrare il viaggio vero.

In questo stato vengono persistiti:

```text
GPS points
sensor windows HAR
state transitions
```

## Dati Usati Dalla FSM

La FSM riceve tre tipi di eventi:

```text
MotionWindowEvaluated
GpsFixReceived
PotentialMotionTimeoutElapsed
```

### MotionWindowEvaluated

Arriva dai sensori inerziali, soprattutto dall'accelerometro.

Contiene:

```text
timestamp
sigma
sampleCount
```

`sigma` misura quanto varia il modulo dell'accelerazione nella finestra osservata. Se `sigma` e alto, il telefono si sta muovendo fisicamente.

Soglia attuale:

```text
movementSigmaThreshold = 1
```

Quindi:

```text
sigma > 1 => movimento fisico del telefono
```

### GpsFixReceived

Arriva da `Geolocator`, quindi dai servizi di localizzazione del sistema operativo:

```text
Android Location Services / Fused Location Provider
iOS CoreLocation
```

Contiene:

```text
timestamp
latitudine
longitudine
speedMetersPerSecond
accuracyMeters
```

La velocita usata dalla FSM non e piu solo `position.speed` nativa. Prima passa da un estimatore.

### PotentialMotionTimeoutElapsed

Evento interno generato se `POTENTIAL_MOTION` dura troppo senza conferma.

Timeout attuale:

```text
60 secondi
```

## Velocita GPS Robusta

La velocita viene calcolata in `GpsSpeedEstimator`.

L'estimatore riceve i fix GPS e produce una velocita in metri al secondo.

### Caso 1: speed nativa credibile

Se il sistema operativo fornisce:

```text
position.speed > 0
position.speed <= 80 m/s
```

allora quella velocita viene usata.

`80 m/s` corrisponde a circa:

```text
288 km/h
```

Quindi valori superiori vengono considerati spike poco credibili.

### Caso 2: speed nativa zero o non credibile

Se `position.speed` e zero o non credibile, l'estimatore usa il fallback:

```text
velocita = distanza tra due fix GPS / tempo trascorso
```

Per farlo servono almeno due fix GPS.

L'estimatore mantiene:

```text
ultimi 5 fix GPS
ultimi 3 valori di speed
```

I fix troppo vecchi vengono ignorati:

```text
lookback massimo: 2 minuti
```

### Filtro anti-rumore

Non ogni piccolo spostamento GPS viene considerato movimento.

Viene calcolata una dead zone in base all'accuratezza:

```text
deadZone = min(12m, max(2m, accuracy * 0.35))
```

Se la distanza tra due fix e dentro questa zona, la velocita stimata resta zero.

### Smoothing

Quando ci sono almeno 3 valori di velocita, viene usata la mediana degli ultimi 3.

Questo riduce picchi tipo:

```text
0 km/h -> 40 km/h -> 3 km/h
```

causati da rumore GPS.

L'estimatore non viene piu azzerato quando cambia il profilo di campionamento, ad esempio da `STATIONARY` a `POTENTIAL_MOTION` o da `POTENTIAL_MOTION` ad `ACTIVE_TRACKING`.

Viene azzerato solo quando:

```text
inizia una nuova sessione
finisce una sessione
```

Questo e importante perche la memoria degli ultimi fix GPS deve sopravvivere proprio nei momenti di transizione.

## Affidabilita GPS

Un fix GPS e considerato affidabile se:

```text
accuracyMeters == null
oppure
accuracyMeters <= 35
```

Quindi:

```text
accuracy <= 35m => GPS affidabile
accuracy > 35m  => GPS non affidabile
```

La FSM usa questa distinzione per richiedere piu conferme quando il GPS e sporco.

## Transizioni Da STATIONARY

### STATIONARY -> POTENTIAL_MOTION via sigma

Succede quando il telefono viene mosso fisicamente.

Regola:

```text
sigma > 1
per 4 finestre consecutive
```

Transizione:

```text
STATIONARY -> POTENTIAL_MOTION
reason = movement_sigma_above_threshold
```

### STATIONARY -> POTENTIAL_MOTION via GPS affidabile

Regola:

```text
2 fix GPS affidabili consecutivi
speed > 2 km/h
```

In unita interne:

```text
speed > 2 / 3.6 m/s
```

Transizione:

```text
STATIONARY -> POTENTIAL_MOTION
reason = gps_reliable_motion_confirmed_in_stationary
```

### STATIONARY -> POTENTIAL_MOTION via GPS non affidabile

Regola:

```text
3 fix GPS non affidabili consecutivi
speed > 2 km/h
```

Transizione:

```text
STATIONARY -> POTENTIAL_MOTION
reason = gps_unreliable_motion_confirmed_in_stationary
```

### GPS affidabile veloce in STATIONARY

Con GPS affidabile, la regola piu importante resta:

```text
2 fix GPS affidabili consecutivi
speed > 2 km/h
```

Questo vale anche se la velocita e gia sopra 8 km/h.

Quindi, se il GPS affidabile vede movimento veloce, la FSM non aspetta ferma il terzo fix: passa a `POTENTIAL_MOTION`, accende profilo stretto e HAR in RAM, e poi conferma `ACTIVE_TRACKING` dal prossimo fix affidabile in `POTENTIAL_MOTION`.

Motivo:

```text
evitare falsi ACTIVE diretti
senza peggiorare il problema originale di aggancio lento
```

Transizione:

```text
STATIONARY -> POTENTIAL_MOTION
reason = gps_reliable_motion_confirmed_in_stationary
```

Il salto diretto `STATIONARY -> ACTIVE_TRACKING` con GPS affidabile resta configurabile nel codice, ma con le soglie attuali il percorso pratico e piu prudente:

```text
STATIONARY -> POTENTIAL_MOTION -> ACTIVE_TRACKING
```

### STATIONARY -> ACTIVE_TRACKING diretto via GPS non affidabile

Regola:

```text
3 fix GPS non affidabili consecutivi
speed > 8 km/h
```

Transizione:

```text
STATIONARY -> ACTIVE_TRACKING
reason = gps_unreliable_fast_speed_confirmed_in_stationary
```

### Reset evidenza GPS in STATIONARY

Se arriva un fix con:

```text
speed <= 2 km/h
```

le evidenze GPS accumulate in `STATIONARY` vengono azzerate.

Inoltre le evidenze affidabili e non affidabili non si mischiano: se arrivano fix affidabili, si azzera il contatore non affidabile; se arrivano fix non affidabili, si azzera il contatore affidabile.

I fix veloci e i fix di movimento normale hanno soglie diverse:

```text
movimento normale:
  speed > 2 km/h

movimento veloce:
  speed > 8 km/h
```

Il movimento normale affidabile puo portare a `POTENTIAL_MOTION`.

Il movimento veloce affidabile passa prima da `POTENTIAL_MOTION`, cosi HAR e GPS stretto partono subito senza dichiarare immediatamente il viaggio definitivo.

Il movimento veloce non affidabile, invece, richiede 3 fix e puo portare direttamente ad `ACTIVE_TRACKING`, perche la soglia non affidabile e gia piu severa.

## Transizioni Da POTENTIAL_MOTION

### POTENTIAL_MOTION -> ACTIVE_TRACKING via GPS affidabile

Regola:

```text
GPS affidabile
speed > 2 km/h
```

Transizione:

```text
POTENTIAL_MOTION -> ACTIVE_TRACKING
reason = gps_speed_above_active_threshold
```

In `POTENTIAL_MOTION` basta un fix GPS affidabile sopra soglia, perche lo stato e gia stato attivato da una precedente evidenza di movimento.

### Timeout e freschezza GPS

Il timeout di `POTENTIAL_MOTION` non usa piu una velocita GPS vecchia o non affidabile per confermare il viaggio.

Regola:

```text
un fix GPS usato al timeout deve essere:
  affidabile
  recente
  con speed > 2 km/h
```

La freschezza attuale e':

```text
ultimo fix affidabile <= 20 secondi fa
```

Questo evita un caso pericoloso:

```text
arriva un fix affidabile fermo
poi arriva uno spike GPS non affidabile
poi scatta il timeout
```

In questa situazione la FSM non deve confermare il viaggio solo perche l'ultima velocita letta era alta.

### POTENTIAL_MOTION -> ACTIVE_TRACKING via motion senza GPS affidabile

Regola:

```text
nessun GPS affidabile disponibile
sigma > 1
per 8 finestre di movimento
```

Transizione:

```text
POTENTIAL_MOTION -> ACTIVE_TRACKING
reason = sustained_motion_without_reliable_gps
```

Serve per non restare bloccati quando il GPS non prende bene.

### POTENTIAL_MOTION -> ACTIVE_TRACKING via timeout confermato

Dopo 60 secondi in `POTENTIAL_MOTION`, il timeout controlla se c'e conferma sufficiente.

Con GPS:

```text
GPS affidabile gia visto
latestSpeed > 2 km/h
```

Transizione:

```text
POTENTIAL_MOTION -> ACTIVE_TRACKING
reason = gps_speed_above_active_threshold
```

Senza GPS affidabile:

```text
motion windows >= 8
```

Transizione:

```text
POTENTIAL_MOTION -> ACTIVE_TRACKING
reason = motion_confirmed_without_reliable_gps
```

## Ritorno Da POTENTIAL_MOTION A STATIONARY

### GPS affidabile dice fermo

Regola:

```text
2 fix GPS affidabili
speed <= 0.1 m/s
```

`0.1 m/s` corrisponde a circa:

```text
0.36 km/h
```

Transizione:

```text
POTENTIAL_MOTION -> STATIONARY
reason = gps_stationary_in_potential_motion
```

### Sensori fermi

Regola:

```text
sigma <= 1
per 4 finestre
```

Transizione:

```text
POTENTIAL_MOTION -> STATIONARY
reason = potential_motion_stationary_windows
```

### Timeout senza conferma

Dopo 60 secondi, se non c'e conferma GPS e non c'e movimento sufficiente:

```text
POTENTIAL_MOTION -> STATIONARY
reason = potential_motion_timeout_without_confirmed_trip
```

## Transizioni Da ACTIVE_TRACKING

### ACTIVE_TRACKING -> STATIONARY

Regola:

```text
latestSpeed <= 0.1 m/s
sigma <= 1
per almeno 2 minuti
```

Transizione:

```text
ACTIVE_TRACKING -> STATIONARY
reason = gps_and_motion_stationary_for_grace_period
```

Quindi per fermare davvero il viaggio servono insieme:

```text
GPS fermo
telefono fisicamente fermo
durata minima di conferma
```

Se uno dei due segnali torna a indicare movimento, il timer di stationary evidence viene azzerato.

## Cosa Viene Salvato Nel DB Locale

### Transizioni FSM

Ogni transizione viene salvata con:

```text
from_state
to_state
reason
timestamp
sigma
speed_mps
```

### GPS points

Vengono salvati solo se il profilo corrente ha:

```text
persistGpsPoints = true
```

Attualmente:

```text
STATIONARY recent/deep: si
POTENTIAL_MOTION: no
ACTIVE_TRACKING: si
```

### Sensor windows HAR

Vengono salvate solo se il profilo corrente ha:

```text
persistSensorWindows = true
```

Attualmente:

```text
STATIONARY recent/deep: no
POTENTIAL_MOTION: no
ACTIVE_TRACKING: si
```

Ogni sensor window rappresenta circa:

```text
5 secondi
500 righe
9 canali
```

I canali sono:

```text
Acc_x, Acc_y, Acc_z
Gyr_x, Gyr_y, Gyr_z
Mag_x, Mag_y, Mag_z
```

## Note Importanti

### GPS interval non e una garanzia

I valori `gpsInterval` e `distanceFilter` sono richieste fatte al sistema operativo, non garanzie assolute.

Android e iOS possono consegnare fix:

```text
piu tardi
piu presto
raggruppati
con accuracy diversa
```

per motivi di batteria, segnale, permessi o policy del sistema.

### Background GPS

Il tracking ora richiede esplicitamente supporto al GPS in background.

Su Android il runtime usa un foreground service tramite notifica persistente durante il tracking.

Permessi dichiarati:

```text
ACCESS_COARSE_LOCATION
ACCESS_FINE_LOCATION
ACCESS_BACKGROUND_LOCATION
FOREGROUND_SERVICE
FOREGROUND_SERVICE_LOCATION
POST_NOTIFICATIONS
```

Su iOS il runtime abilita:

```text
allowBackgroundLocationUpdates = true
showBackgroundLocationIndicator = true
UIBackgroundModes = location
```

Nota pratica: su iOS l'utente deve concedere permessi compatibili con il tracking in background. Se concede solo un permesso limitato, il sistema operativo puo comunque ridurre o bloccare gli update quando l'app non e in primo piano.

### STATIONARY recent e piu costoso

Il profilo recent usa GPS high accuracy ogni circa 20 secondi. Consuma piu batteria del vecchio profilo low power, ma serve a evitare il problema in cui l'utente parte in macchina e il telefono resta fisicamente fermo.

Dopo 10 minuti di fermo continuativo si passa a `STATIONARY deep` per ridurre il consumo.

### Il GPS puo svegliare la FSM

La modifica principale rispetto alla logica precedente e che il GPS ora puo far uscire da `STATIONARY`.

Prima il sistema dipendeva troppo dal sigma: se il telefono era fermo sul sedile dell'auto, la FSM poteva restare bloccata in `STATIONARY`.

Ora:

```text
telefono fermo fisicamente
GPS mostra movimento coerente
FSM puo passare a POTENTIAL_MOTION o ACTIVE_TRACKING
```

## Sintesi Operativa

```text
STATIONARY recent:
  controllo GPS reattivo per capire se riparti

STATIONARY deep:
  risparmio batteria quando sei fermo da tanto

POTENTIAL_MOTION:
  zona di verifica, HAR attivo ma non persistito

ACTIVE_TRACKING:
  viaggio confermato, GPS e HAR persistiti
```

La FSM ora combina:

```text
movimento fisico del telefono
velocita GPS nativa
velocita GPS stimata da distanza/tempo
affidabilita del fix GPS
timeout e finestre consecutive
```

Questo rende il sistema piu robusto nei casi in cui il telefono non si muove fisicamente ma l'utente si sta muovendo nello spazio, come auto, bus o treno.
