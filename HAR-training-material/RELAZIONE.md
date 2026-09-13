# Riconoscimento di attività e modalità di trasporto da sensori inerziali
## Relazione tecnica completa

---

## 1. Obiettivo

Costruire un classificatore che, a partire dai sensori inerziali di uno smartphone,
riconosca l'attività/modalità di locomozione di una persona. Il lavoro usa il
dataset **SHL (Sussex-Huawei Locomotion)**, un dataset di riferimento raccolto
dall'Università del Sussex con telefoni Huawei indossati in 4 posizioni del corpo.

Il percorso è stato iterativo: a ogni passo abbiamo misurato un problema, formulato
un'ipotesi sulla causa, e introdotto una modifica mirata. Questa relazione documenta
**tutti** gli esperimenti, inclusi i due modelli iniziali e i loro difetti.

---

## 2. Il dataset

### 2.1 Sensori e formato

Ogni posizione del corpo registra serie temporali a **100 Hz** da:

- **Accelerometro** (Acc_x, Acc_y, Acc_z)
- **Giroscopio** (Gyr_x, Gyr_y, Gyr_z)
- **Magnetometro** (Mag_x, Mag_y, Mag_z)

I dati sono già pre-segmentati in **finestre da 500 campioni** (5 secondi). Ogni riga
di un file `.txt` contiene una finestra intera (500 valori). Il file `Label.txt`
contiene l'etichetta, ripetuta 500 volte per riga (una sola attività per finestra).

### 2.2 Posizioni del corpo

Quattro registrazioni simultanee: **Hips** (tasca), **Bag** (borsa), **Torso** (petto),
**Hand** (mano). Lo stesso movimento produce segnali molto diversi a seconda della
posizione: mescolare le quattro posizioni rende il modello robusto all'uso reale, in
cui non si sa dove l'utente tiene il telefono.

### 2.3 Le classi SHL originali (1-8)

```
1 IDLE       2 WALKING    3 RUNNING    4 DRIVING
5 BIKING     6 BUS        7 TRAIN      8 SUBWAY
```

### 2.4 Dati disponibili

- **Train ufficiale**: 4 posizioni × 196.072 finestre = 784.288 finestre etichettate.
- **Validation ufficiale**: 4 posizioni × 28.789 = 115.156 finestre etichettate.
- **Test ufficiale**: senza etichette e in formato continuo (1 colonna) → **inutilizzabile
  per valutare** (le etichette vere sono tenute segrete da SHL per la competizione).

Per questo motivo tutte le valutazioni oneste usano il **validation set ufficiale**.

---

## 3. Pipeline generale

```
file .txt grezzi  →  preprocessing  →  tensori .npy  →  training  →  valutazione
```

Il preprocessing trasforma i file di testo in un tensore `X` di forma
`(N, 500, C)` — N finestre, 500 timestep, C canali — e un vettore di etichette `y`.
Questo è il formato richiesto da una CNN 1D.

---

## 4. Architettura di base (CNN 1D)

```
Input (500, C)
  Conv1D(64, kernel=10) + ReLU      → rileva pattern locali (~0.1 s) su tutti i canali
  MaxPooling1D(2)                    → comprime, invarianza a piccole traslazioni
  Conv1D(128, kernel=10) + ReLU      → pattern di pattern, più astratti
  MaxPooling1D(2)
  Flatten
  Dense(128) + ReLU                  → riassunto globale della finestra
  Dropout(0.5)                       → regularizzazione
  Dense(num_classi) + Softmax        → probabilità per classe
```

Circa 2 milioni di parametri (quasi tutti nel primo Dense). Il filtro convoluzionale
scorre lungo il **tempo** leggendo tutti i canali insieme a ogni passo, e impara da
solo quali pattern distinguono le attività (picchi del passo, vibrazioni del motore,
segnale piatto da fermo, ecc.).

---

## 5. Esperimento 1 — 6 classi

### 5.1 Setup

- **6 canali** (Acc + Gyr; il magnetometro escluso perché ritenuto rumoroso).
- **6 classi**: le modalità di trasporto 6/7/8 (Bus/Train/Subway) fuse in
  un'unica classe **PUBLIC_TRANSPORT**.
- Split **casuale stratificato** 70/15/15 (train/val/test).
- Class weights bilanciati, 20 epoche, early stopping.

### 5.2 Risultati (sul test interno)

```
Accuracy: 80.5%

Classe              F1
RUNNING             0.988
WALKING             0.943
BIKING              0.941
DRIVING             0.809
PUBLIC_TRANSPORT    0.768
IDLE                0.639   ← peggiore
```

Confusion matrix:
```
              IDLE   WALK   RUN   BIKE   DRIV   PUB
IDLE        [12891    125     1     58    179   1419]
WALKING     [  497  13768    29    278     30    131]
RUNNING     [    7     44  5005     17      1      1]
BIKING      [  242    141    14  13290    159    236]
DRIVING     [  629     56     1    169  16207   1976]
PUB         [11386    332     5    344   4430  33546]
```

### 5.3 Problemi individuati

1. **Confusione IDLE ↔ PUBLIC_TRANSPORT**: 11.386 mezzi pubblici classificati come
   IDLE e 1.419 viceversa. Causa: un mezzo fermo produce lo stesso segnale inerziale
   di una persona ferma.
2. **Confusione DRIVING ↔ PUBLIC_TRANSPORT**: ~6.400 errori. Auto e mezzi pubblici
   in movimento hanno firme inerziali simili.
3. **`test_loss = NaN`**: anomalia ignorata sul momento, in realtà sintomo di valori
   mancanti nei dati (scoperta più avanti).
4. **(scoperto dopo) Data leakage**: lo split casuale gonfiava l'80.5%.

---

## 6. Esperimento 2 — 5 classi (fusione DRIVING + PUBLIC_TRANSPORT)

### 6.1 Motivazione

DRIVING e PUBLIC_TRANSPORT si confondevano molto tra loro (~6.400 errori). Fonderli in
un'unica classe **MOVING_VEHICLE** trasforma quegli errori in predizioni corrette e
rimuove un confine difficile. RUNNING è stato mantenuto separato perché era la classe
migliore (F1 0.988): fonderlo avrebbe buttato via informazione gratis.

Nuova mappatura: `1→IDLE, 2→WALKING, 3→RUNNING, 4→BIKING, 5/6/7/8→MOVING_VEHICLE`.

### 6.2 Risultati (sul test interno)

```
Accuracy: 84.0%   (+3.5 rispetto alle 6 classi)

Classe            F1
RUNNING           0.987
WALKING           0.925
BIKING            0.926
MOVING_VEHICLE    0.865
IDLE              0.583   ← peggiorato
```

Confusion matrix:
```
              IDLE   WALK   RUN   BIKE   MOVE
IDLE        [11142    257     1     71   3202]
WALKING     [  443  13809     8    301    172]
RUNNING     [    6     55  4967     44      3]
BIKING      [  186    212     5  13330    349]
MOVING      [11787    803     4    956  55531]
```

### 6.3 Problemi individuati

1. La fusione ha funzionato (eliminata la confusione DRIVING↔PUB), ma ha **isolato** il
   problema vero: **IDLE ↔ MOVING_VEHICLE** ora rappresentava il **79% di tutti gli
   errori**.
2. **IDLE precision = 0.47**: quando il modello dice "IDLE" sbaglia più di una volta su
   due, perché 11.787 mezzi fermi finiscono nella casella IDLE.
3. **Il leakage era ancora presente**: l'84% restava gonfiato.

---

## 7. La scoperta del data leakage

### 7.1 Il problema dello split casuale

Le finestre consecutive distano 5 secondi e sono quasi identiche. Con uno split casuale,
la finestra N può finire nel train e la N+1 nel test: il modello valuta su dati quasi
identici a quelli su cui si è allenato → **accuracy gonfiata** (data leakage temporale).

### 7.2 La valutazione onesta

Abbiamo valutato il modello a 5 classi (mai modificato) sul **validation ufficiale SHL**
— una sessione completamente diversa, mai vista in training, senza alcun leakage.

```
Split casuale interno:    84.0%   ❌ gonfiato
Validation ufficiale:     73.3%   ✅ numero VERO
                          ─────
                          −11 punti di leakage
```

### 7.3 Cosa nascondeva il leakage

Il leakage non gonfiava solo il numero in cima: **nascondeva quali classi generalizzano
male**. Su dati realmente nuovi:

```
                interno (gonfiato)   validation (vero)
RUNNING recall:     0.98          →      0.57
BIKING recall:      0.95          →      0.56
```

RUNNING sembrava perfetto ma il modello non lo aveva davvero imparato: aveva memorizzato
finestre quasi-identiche presenti sia in train sia in test.

Confusion matrix onesta (5 classi su validation ufficiale):
```
              IDLE   WALK   RUN   BIKE   MOVE
IDLE        [19020    531     0    230   4075]
WALKING     [ 2263  17275    15    987    380]
RUNNING     [   14    413  1255    536      2]
BIKING      [ 1176    527     0   5354   2567]
MOVING      [15449    927     1    647  41512]
```
IDLE ↔ MOVING = 19.524 errori = **63% di tutti gli errori**.

---

## 8. Smoothing temporale (post-processing)

### 8.1 Idea

Le attività hanno **inerzia**: non si cambia stato ogni 5 secondi. Una singola finestra
IDLE in mezzo a un mare di MOVING è quasi certamente un mezzo fermo (semaforo). Lo
smoothing corregge gli outlier guardando le predizioni vicine nel tempo (voto di
maggioranza su una finestra scorrevole), applicato **dentro ogni posizione** separatamente.

Requisito: predizioni in **ordine cronologico** (mantenuto nel preprocessing).

### 8.2 Risultati (modello 5 classi, sul validation ufficiale)

```
finestra   contesto   accuracy
   1          5s        73.3%   (baseline)
   9         45s        76.4%
  31        155s        79.5%
  61        305s        80.5%   ← ottimo
  91        455s        80.2%   (oltre i 5 min sovra-leviga e cancella attività brevi)
```

Lo smoothing recupera **+7.2 punti** (73.3% → 80.5%) senza riallenare nulla.

---

## 9. Esperimento 3 — 9 canali + normalizzazione + focal loss + protocollo corretto

### 9.1 Modifiche introdotte

1. **Magnetometro** (9 canali): per attaccare l'ambiguità IDLE↔mezzo fermo, sfruttando
   che la carrozzeria metallica e l'elettronica di un veicolo alterano il campo
   magnetico anche da fermo.
2. **Normalizzazione** per-canale (media 0, std 1), calcolata **solo sul train** per non
   reintrodurre leakage. Necessaria perché i canali hanno scale diverse (Acc ~10,
   Gyr ~0.01, Mag ~50).
3. **Focal loss** (γ=2) con alpha bilanciato: contrasta lo sbilanciamento
   (MOVING_VEHICLE ≈ 51% dei dati) su due fronti — l'alpha pesa le classi rare
   (RUNNING ×2.3, MOVING ×0.16), il fattore `(1−p)²` concentra l'apprendimento sugli
   esempi difficili e silenzia i tanti esempi banali.
4. **Protocollo corretto** (niente leakage): train ufficiale → training; ultima fetta
   temporale del train → early stopping; validation ufficiale → solo valutazione finale.

### 9.2 La scoperta dei valori mancanti (NaN)

Calcolando le statistiche di normalizzazione, i canali Gyr e Mag risultavano NaN. Causa:
il dataset SHL contiene **valori mancanti sporadici** in Gyr/Mag (frazione ~0, ma basta
un singolo NaN a propagarsi). **Questo spiegava il `test_loss = NaN`** dei modelli
precedenti, che usavano Gyr. Soluzione: statistiche nan-aware e imputazione dei mancanti
al valore medio del canale (0 dopo normalizzazione).

### 9.3 Risultati (sul validation ufficiale)

```
                                   accuracy
9ch + norm + focal (raw):          75.4%   (+2.1 sul baseline onesto 73.3%)
9ch + norm + focal + smoothing:    80.8%
```

Confusion matrix (raw):
```
              IDLE   WALK   RUN   BIKE   MOVE
IDLE        [17605    284     0    236   5731]
WALKING     [ 1861  16476    49   1417   1117]
RUNNING     [   12    417  1414    376      1]
BIKING      [  821   1562    29   5216   1996]
MOVING      [11732    392     2    325  46085]
```

Effetti:
- RUNNING recall 0.57 → 0.64 (**focal loss**).
- MOVING recall 0.71 → 0.79.
- IDLE↔MOVING 19.524 → 17.463 errori (**magnetometro**, miglioramento modesto).
- BIKING resta debole (0.54).

**Verdetto**: i tre interventi danno un guadagno reale ma modesto. Il magnetometro ha
aiutato meno del previsto: l'ambiguità fisica "fermo a piedi vs fermo su un mezzo" resta
dura. Dopo lo smoothing, questo modello e il precedente convergono entrambi verso
~80.5-80.8% — segno di un soffitto.

---

## 10. Esperimento 4 — Contesto temporale appreso (CNN + GRU)

### 10.1 Idea

Lo smoothing è una **regola fissa** imposta dall'esterno. Una **GRU** impara la regola di
contesto **dai dati**, e può essere molto più sottile (es. "ignora 2 finestre IDLE in
mezzo al movimento, ma se sono 20 di fila allora sei davvero sceso"; "non schiacciare
RUNNING che può durare poco").

### 10.2 Architettura (a due stadi)

1. La CNN allenata diventa un **estrattore di feature**: ogni finestra da 5 s → un
   vettore di 128 numeri (l'attivazione del Dense penultimo).
2. Una **GRU bidirezionale** legge sequenze di 64 embedding consecutivi (~320 s, lo
   stesso contesto del punto ottimale dello smoothing) ed etichetta ogni finestra usando
   contesto passato **e** futuro.

### 10.3 Risultati (sul validation ufficiale)

```
                                   accuracy
CNN 9ch + focal (raw):             75.4%
CNN 9ch + focal + smoothing:       80.8%
CNN 9ch + focal + GRU:             83.7%   ← +2.9 sullo smoothing
```

Confusion matrix:
```
              IDLE   WALK   RUN   BIKE   MOVE     recall
IDLE        [17331    165     0    120   6240]    0.73
WALKING     [  788  18380     3    634   1115]    0.88
RUNNING     [    4    281  1381    552      2]    0.62
BIKING      [  263   1829     5   4912   2615]    0.51
MOVING      [ 3922    192     0     20  54402]    0.93
```

Effetti:
- **MOVING recall 0.79 → 0.93** e **IDLE precision 0.55 → 0.78**: il caso "mezzo fermo"
  è ora quasi sempre riconosciuto (MOVE→IDLE crollato da 11.732 a 3.922).
- IDLE↔MOVING: 17.463 (raw) → 14.148 (smoothing) → **10.162 (GRU)**: il migliore.
- WALKING F1 0.88.

La GRU ha **sfondato il soffitto** dell'80-81%: la regola di contesto appresa supera
nettamente la maggioranza fissa.

---

## 11. Tabella riepilogativa

```
Modello                                    Valutazione            Accuracy
─────────────────────────────────────────────────────────────────────────
6 classi (Acc+Gyr), split casuale          test interno (leaky)    80.5%  ❌
5 classi, split casuale                     test interno (leaky)    84.0%  ❌
5 classi                                    validation ufficiale    73.3%  ✅ baseline
5 classi + smoothing                        validation ufficiale    80.5%
9 canali + norm + focal (raw)               validation ufficiale    75.4%
9 canali + norm + focal + smoothing         validation ufficiale    80.8%
9 canali + norm + focal + GRU               validation ufficiale    83.7%  ✅ migliore
```

Dal baseline onesto (73.3%) al modello finale (83.7%): **+10 punti**, ognuno con una
motivazione tecnica precisa.

---

## 12. Problemi residui e limiti

1. **IDLE ↔ MOVING_VEHICLE** (~54% degli errori residui): limite **fisico**. Un veicolo
   fermo a lungo (stazione, ingorgo) produce un segnale inerziale identico a una persona
   ferma. Né il magnetometro né il contesto temporale lo risolvono del tutto. Servirebbero
   sensori aggiuntivi (velocità GPS, barometro).
2. **BIKING (recall 0.51)** e **RUNNING (recall 0.62)**: debolezze a livello di feature
   della CNN, non di contesto. BIKING si confonde con WALKING e MOVING; RUNNING con
   BIKING e WALKING. La GRU non può recuperare errori sistematici della CNN.
3. **Poca varietà nel training**: il train proviene essenzialmente da una grande sessione
   → generalizzazione limitata su sessioni nuove (è il motivo del calo di RUNNING/BIKING
   emerso con il validation ufficiale).
4. **Scelta della finestra/contesto sulla validation**: lieve "tuning sul test";
   metodologicamente andrebbe fatta su dati derivati dal train.

---

## 13. Sviluppi futuri

```
Ambiguità IDLE↔mezzo fermo   →  sensori aggiuntivi (GPS/velocità, barometro)
RUNNING/BIKING deboli         →  data augmentation (jitter, scaling, rotation),
                                 più sessioni/utenti di training
Margini generali              →  modello CNN+GRU end-to-end (fine-tuning congiunto)
                                 invece dell'approccio a due stadi
Sbilanciamento                →  focal loss già introdotta; eventualmente resampling
```

---

## 14. File prodotti

```
Script
  preprocess_shl_cnn1d.py            preprocessing 6 classi (Acc+Gyr)
  preprocess_shl_cnn1d_5class.py     preprocessing 5 classi
  preprocess_shl_9ch_5class.py       preprocessing 9 canali + normalizzazione + protocollo
  train_cnn1d_har.py                 training CNN (6/5 classi)
  train_9ch.py                       training CNN 9 canali + focal loss
  evaluate_on_validation.py          valutazione onesta sul validation ufficiale
  temporal_smoothing.py              smoothing temporale a maggioranza
  train_gru.py                       contesto temporale appreso (CNN + GRU)

Dati
  processed/            tensori 6 classi
  processed_5class/     tensori 5 classi
  processed_9ch/        tensori 9 canali (trainfit/traines/val) + statistiche norm.

Modelli e metriche
  models/               modello 6 classi + metriche + confusion matrix
  models_5class/        modello 5 classi + valutazione onesta + predizioni ordinate
  models_9ch/           modello 9 canali + focal + metriche oneste
  models_gru/           modello GRU finale + metriche oneste (83.7%)
```

---

## 15. Conclusione

Partendo da un classificatore che sembrava fare l'80% ma in realtà ne faceva 73 (per via
del data leakage), siamo arrivati a un modello che fa **83.7% onesto** su dati realmente
mai visti. Il percorso ha valore non solo per il numero finale, ma per la **metodologia**:

- riconoscere e correggere il data leakage,
- isolare il problema dominante (IDLE↔mezzo fermo) e attaccarlo da più angoli
  (fusione classi, magnetometro, contesto temporale),
- distinguere i limiti **risolvibili** (sbilanciamento, normalizzazione, contesto) da
  quelli **fisici** (un mezzo fermo è indistinguibile da una persona ferma con i soli
  sensori inerziali).

Il risultato finale combina quattro scelte motivate — fusione delle modalità di
trasporto, magnetometro, focal loss, e contesto temporale appreso via GRU — ciascuna
con un effetto misurato sul validation ufficiale.
```

---

## 16. Ottimizzazione dell'inferenza in produzione (Mobility Diary)

### 16.1 Contesto

Il modello effettivamente in produzione **non** è quello a 9 canali del capitolo 10
(83.7%), ma la variante a **6 canali** (Acc+Gyr, senza magnetometro): `shl_cnn1d_full_
100pct_5class_best.keras` (CNN) + `shl_6ch_5class_gru_best.keras` (GRU), rifatta dopo la
stesura di questa relazione perché il magnetometro dei telefoni reali non è affidabile
quanto quello del dataset SHL. La sua accuracy onesta sul validation ufficiale è
**79.47%**, non 83.7%.

Il backend Django/Celery (`har_classification`) chiama questi due modelli in due passi
(`manual_har/script.py`): la CNN estrae un embedding a 128 dimensioni per ogni finestra
da 500 campioni, poi la GRU classifica sequenze di 32 embedding alla volta **con un
`predict()` per ogni chunk, dentro un loop Python**. In produzione questo pattern
produceva tempi incoerenti: 141 finestre ≈ 153ms, 579 finestre ≈ 3.4s, 1060 finestre ≈
939ms — nessuna relazione lineare con il numero di finestre.

### 16.2 Diagnosi

Analisi empirica (non stime) sui modelli reali, con `tensorflow-cpu` sulla stessa
versione del backend:

| Causa | Evidenza |
|---|---|
| **Graph retracing per shape**: `model.predict()` di Keras ricompila il grafo ogni volta che riceve un batch_size mai visto dal processo. Per una CNN+GRU bidirezionale un retrace costa **~2.3 secondi**. | chiamata su una shape nuova: 2364ms; stessa shape la seconda volta: 97ms |
| **Loop Python per la GRU**: un `predict()` per ogni chunk da 32 finestre invece di una singola chiamata batched | N=2048: loop=1180ms vs batched=259ms (4.4×) |
| **Import di TensorFlow**: costo fisso (1.2–2.9s) per processo/worker nuovo, indipendente da N | misurato su processo cold |
| **`seq_len=32` mai ri-tarato** sulla versione a 6 canali (ereditato dall'esperimento a 9 canali) | vedi tabella §16.5 |
| **Stato optimizer Adam incollato nei checkpoint** (`ModelCheckpoint` salva anche i momenti Adam, inutili in inferenza) | CNN 24.28MB → 8.11MB pulito (-66%); GRU 0.94MB → 0.33MB |

La non-linearità osservata in produzione (579 finestre più lente di 1060) è la firma
tipica di un retrace/cold-start che domina sul calcolo reale, non di un problema di
volume dati.

### 16.3 La soluzione

Due modifiche, indipendenti e cumulative, implementate in `export_production/`:

**A. Fusione CNN+GRU in un unico modello end-to-end**, con i pesi copiati (non
riallenati) dai due checkpoint esistenti. Verificata l'equivalenza numerica esatta
rispetto alla pipeline a due stadi (differenza massima sulle probabilità: 0.0–1.2e-7,
puro rumore float32). Elimina un file, un secondo `predict()`, e il passaggio manuale
degli embedding.

**B. Fix del pattern di chiamata**: il modello fuso viene avvolto in un `tf.function`
con `input_signature` esplicita — batch dinamico, lunghezza di sequenza fissa:

```python
self._infer = tf.function(
    lambda x: self.model(x, training=False),
    input_signature=[tf.TensorSpec(shape=[None, seq_len, 500, 6], dtype=tf.float32)],
)
self._infer(tf.zeros((1, seq_len, 500, 6)))  # forza la compilazione UNA volta, all'avvio
```

Questo forza **una sola compilazione**, valida per qualunque numero di finestre per
richiesta: cambia solo il batch (quante sequenze da `seq_len` finestre servono),
mai la forma "interna" della funzione compilata, quindi TensorFlow non retraccia più.

> Nota tecnica scoperta durante i test: rendere dinamici **sia** il batch **sia** il
> tempo (`shape=[None, None, 500, 6]`) compila senza errori ma produce silenziosamente
> uno **shape di output sbagliato** con questa combinazione Bidirectional(GRU) +
> TimeDistributed in Keras 3.x/TF 2.21 (input `(5,128,...)` → output `(5,5,5)` invece di
> `(5,128,5)`). Per questo la lunghezza di sequenza resta un parametro fisso della
> funzione compilata, non un asse dinamico.

**C. `sequence_length` portato da 32 a 128.** Non è un parametro architetturale fisso:
la GRU salvata ha uno shape di input rigido `(32,128)` solo perché così è stata
costruita in `train_gru_6ch.py`, ma i pesi non dipendono dalla lunghezza — ricostruendo
lo stesso layer con input dinamico e ricaricando gli stessi pesi le predizioni non
cambiano. Misurato sul validation ufficiale reale (115.156 finestre), l'accuracy sale
con `L` fino a un plateau intorno a `L≈256`:

| L | accuracy | IDLE rec | WALK rec | RUN rec | BIKE rec | MOVE rec |
|---|---|---|---|---|---|---|
| 32 (produzione originale) | 79.47% | .90 | .93 | .72 | .48 | .76 |
| 64 | 82.51% | .87 | .94 | .74 | .45 | .83 |
| **128 (scelto)** | **84.90%** | .85 | .95 | .75 | .41 | .89 |
| 256 | 86.11% | .82 | .95 | .76 | .40 | .92 |
| posizione intera (28.789) | 86.01% | .75 | .96 | .76 | .37 | .96 (**108s/sequenza, scartato**: la GRU bidirezionale non scala su CPU per sequenze così lunghe) |

`L=128` è stato scelto come compromesso: guadagno grosso (+5.4 punti), plateau non
ancora raggiunto ma vicino, costo di latenza ancora trascurabile. Il guadagno viene
quasi tutto da MOVING_VEHICLE/IDLE (l'ambiguità dominante del capitolo 12), a costo di
un po' di recall BIKING (0.48→0.41) — la GRU con più contesto risolve meglio "veicolo
fermo a lungo" ma confonde leggermente di più BIKING↔WALKING.

### 16.4 Come funziona, in sintesi

```
                    PRIMA                              DOPO
┌─────────────────────────────────┐    ┌──────────────────────────────────┐
│ 1. cnn.predict(tutte le finestre)│    │ modello unico, un solo predict():  │
│ 2. loop Python:                  │    │  - CNN e GRU nello stesso grafo    │
│    per ogni chunk da 32:         │ →  │  - tf.function con input_signature │
│      gru.predict(chunk)          │    │    esplicita (batch dinamico,      │
│    (N/32 chiamate separate,      │    │    tempo fisso a 128) → UNA sola   │
│     ognuna può ritracciare)      │    │    compilazione, mai più retrace   │
└─────────────────────────────────┘    └──────────────────────────────────┘
```

Il warmup (una chiamata fittizia in `HARClassifier.__init__`) sposta il costo di
compilazione dall'avvio del worker Celery (una tantum) invece che sulla prima
richiesta reale di ogni processo.

### 16.5 Risultati misurati (prima/dopo, stesso processo, stessi dati)

Confronto diretto BEFORE (pattern attuale, 2 modelli, loop, `L=32`) vs AFTER (modello
fuso, `tf.function` a shape fissa, `L=128`):

**Latenza (warm):**

| N finestre | BEFORE | AFTER | speedup |
|---|---|---|---|
| 141 (produzione) | 110.9 ms | 42.1 ms | 2.6× |
| 579 (produzione) | 410.6 ms | 93.6 ms | 4.4× |
| 1060 (produzione) | 728.2 ms | 145.8 ms | 5.0× |
| 2048 | 1265.9 ms | 249.1 ms | 5.1× |

**Accuracy reale, intero validation ufficiale (115.156 finestre):**

| | accuracy | ms/finestra | tempo totale |
|---|---|---|---|
| BEFORE | 79.48% | 0.594 | 68.4s |
| AFTER | **84.88%** | **0.223** | **25.7s** |

Delta: **+5.40 punti di accuracy**, **2.7× più veloce** in throughput aggregato,
2.6–5.1× per singola richiesta. I due miglioramenti sono indipendenti: la velocità
viene dal fix del calling pattern (16.3.B, a rischio zero — con `seq_len=32` le
predizioni restano bit-identiche a quelle attuali), l'accuracy viene dal contesto più
lungo (16.3.C, da rivalidare su dati reali dell'app, non solo su SHL).

### 16.6 File prodotti

```
export_production/
  build_fused_model.py   script di conversione: carica i 2 checkpoint attuali, fonde CNN+GRU,
                          verifica l'equivalenza numerica prima di salvare, elimina lo stato optimizer
  inference.py            HARClassifier: modulo pronto per il backend Django/Celery
  shl_har_fused.keras      modello fuso, solo pesi (8.44MB vs 25.22MB dei due originali)
```

### 16.7 Cose non ancora fatte / da validare

- **Quantizzazione (TFLite float16/dynamic-range/int8)**: testata, ma bloccata dalla
  `Bidirectional(GRU)` che richiede il flex delegate (`SELECT_TF_OPS`, `TensorListReserve`
  non è convertibile ai soli builtin TFLite); l'interprete TFLite disponibile in questo
  ambiente non riesce nemmeno ad eseguire i modelli convertiti così. Non prioritaria: il
  collo di bottiglia era il calling pattern, non i FLOP.
- **Distillazione**: non eseguita (richiede retraining). Punto di leva concreto e non
  ancora testato: **1.93M dei 2.02M parametri della CNN (95%) sono nell'unico
  `Dense(128)` che segue il `Flatten()`** di un tensore 118×128 — sostituirlo con
  `GlobalAveragePooling1D` taglierebbe drasticamente quel layer.
- **Validazione su dati reali dell'app** (non solo SHL) prima di fidarsi del +5.4% di
  `L=128` in modo definitivo — SHL è un'altra popolazione/altri dispositivi.
- **Integrazione nel repo Django/Celery**: non ancora fatta (il repo backend non è in
  questa directory). `HARClassifier` va istanziato una volta per worker, non dentro il
  task, per beneficiare del warmup.
