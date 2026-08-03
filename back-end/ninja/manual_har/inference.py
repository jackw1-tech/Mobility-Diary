#!/usr/bin/env python3
"""
Modulo di inferenza per il backend Django/Celery di Mobility Diary.
Sostituisce il caricamento dei due modelli (CNN + GRU) e il loop di predizione
di manual_har/script.py con UNA sola chiamata su un modello fuso, wrappata in un
tf.function a shape esplicitamente dinamica per evitare il retracing.

Uso previsto nel task Celery `har_classification`:

    from inference import HARClassifier

    _classifier = HARClassifier("shl_har_fused.keras")  # istanziato UNA VOLTA per worker

    def har_classification(sensor_windows):  # sensor_windows: np.ndarray (N, 500, 6) float32
        return _classifier.predict(sensor_windows)

Note importanti rispetto alla pipeline precedente:

1. NESSUNA normalizzazione manuale: il modello e' stato allenato su valori grezzi
   (Acc/Gyr cosi' come arrivano dal sensore), quindi le finestre vanno passate senza
   z-score. (Il commento "il modello a 6 canali usa BatchNormalization interni" nello
   script.py originale e' impreciso: il modello non contiene alcun layer di
   BatchNormalization, semplicemente il training non ha mai normalizzato i dati.
   Il comportamento corretto -- passare i dati grezzi -- resta lo stesso, ma va
   capito che dipende dal preprocessing di training, non da un layer nel grafo.)

2. Lunghezza di sequenza passata a runtime (default 128 invece di 32): sul validation
   ufficiale SHL questo porta l'accuracy dal 79.5% (L=32, pipeline attuale) all'84.9%
   (L=128), a parita' di pesi, senza alcun retraining. Vedi il report per i trade-off.

3. Le classi native del modello sono, in ordine: IDLE, WALKING, RUNNING, BIKING,
   MOVING_VEHICLE. Il modello produce gia' "MOVING_VEHICLE" nativamente (la fusione
   DRIVING/BUS/TRAIN/SUBWAY -> MOVING_VEHICLE avviene in training, non nel backend):
   non serve alcun mapping DRIVING -> MOVING_VEHICLE lato Django, e' gia' cosi'.

4. CAUSA PRINCIPALE DEI PICCHI DI LATENZA OSSERVATI (es. 579 finestre = 3.4s):
   `model.predict()` di Keras ricompila (retraces) il suo grafo interno ogni volta
   che riceve una combinazione (batch_size, sequence_length) mai vista prima dal
   processo, e per QUESTO modello (CNN convoluzionale + RNN bidirezionale) il costo
   di un retrace misurato e' ~2.3 SECONDI, non i ~50ms tipici di un modello feed-forward
   semplice. Con richieste di dimensione variabile (141, 579, 1060 finestre...) quasi
   ogni chiamata puo' generare un nuovo batch_size e quindi un nuovo retrace, anche a
   processo/worker gia' "caldo". La soluzione (implementata sotto) e' avvolgere il
   modello in un tf.function con input_signature esplicita: batch dinamico
   (`shape=[None, seq_len, 500, 6]`), ma lunghezza di sequenza FISSA. Questo forza UNA
   SOLA compilazione valida per qualsiasi numero di finestre.

   ATTENZIONE: rendere DINAMICI SIA il batch SIA il tempo (`[None, None, 500, 6]`)
   sembra funzionare (compila, non solleva errori) ma in Keras 3.x + TF 2.21 produce
   silenziosamente uno shape di output SBAGLIATO con questa combinazione di
   Bidirectional(GRU)+TimeDistributed: l'asse tempo dell'output collassa erroneamente
   alla dimensione del batch (verificato: input (5,128,...) -> output (5,5,5) invece di
   (5,128,5)). Per questo motivo qui la lunghezza di sequenza resta un parametro FISSO
   della funzione compilata (non del batch), mentre solo il numero di sequenze per
   richiesta e' dinamico.
"""
from __future__ import annotations

import numpy as np
import tensorflow as tf

CLASS_NAMES = ["IDLE", "WALKING", "RUNNING", "BIKING", "MOVING_VEHICLE"]
DEFAULT_SEQ_LEN = 128


class HARClassifier:
    """Wrapper attorno al modello fuso CNN+GRU. Istanziare UNA volta per processo
    worker (es. modulo a livello di app Django/Celery, non dentro il task) cosi' il
    costo di import/caricamento/primo-trace viene pagato una sola volta all'avvio
    del worker e non ad ogni task."""

    def __init__(self, model_path: str, seq_len: int = DEFAULT_SEQ_LEN):
        self.model = tf.keras.models.load_model(model_path, compile=False)
        self.seq_len = seq_len

        # tf.function con batch dinamico ma lunghezza di sequenza FISSA: una SOLA
        # traccia compilata gestisce qualunque numero di finestre/sequenze per
        # richiesta, eliminando il retracing per-shape che altrimenti costa secondi
        # a ogni nuova dimensione di batch (vedi nota 4 sopra: NON rendere anche il
        # tempo dinamico, produce shape di output errati con questo modello/versione).
        @tf.autograph.experimental.do_not_convert
        def infer(x):
            return self.model(x, training=False)

        self._infer = tf.function(
            infer,
            input_signature=[tf.TensorSpec(shape=[None, seq_len, 500, 6], dtype=tf.float32)],
        )
        # Forza la compilazione ora, all'avvio del worker, non alla prima richiesta reale.
        self._infer(tf.zeros((1, seq_len, 500, 6), dtype=tf.float32))

    def predict(self, windows: np.ndarray) -> dict:
        """windows: array (N, 500, 6) float32, finestre grezze in ordine cronologico
        (tutte della STESSA sessione/posizione: non mescolare sessioni diverse in una
        singola chiamata, la GRU bidirezionale usa contesto passato e futuro).

        Ritorna dict con:
          "labels":  array (N,) int64        -- indice di classe predetto
          "probs":   array (N, 5) float32     -- probabilita' per classe
          "classes": CLASS_NAMES
        """
        windows = np.asarray(windows, dtype=np.float32)
        if windows.ndim != 3 or windows.shape[1:] != (500, 6):
            raise ValueError(f"Shape attesa (N, 500, 6), ricevuta {windows.shape}")

        n = windows.shape[0]
        n_seq = -(-n // self.seq_len)  # ceil division
        pad = n_seq * self.seq_len - n
        if pad:
            windows = np.concatenate([windows, np.zeros((pad, 500, 6), np.float32)])

        sequences = windows.reshape(n_seq, self.seq_len, 500, 6)

        # UNA SOLA chiamata per l'intera richiesta, sulla funzione gia' compilata
        # una volta per tutte in __init__: nessun loop Python, nessun retrace.
        probs = self._infer(tf.constant(sequences)).numpy()
        probs = probs.reshape(n_seq * self.seq_len, len(CLASS_NAMES))[:n]
        labels = np.argmax(probs, axis=-1)

        return {"labels": labels, "probs": probs, "classes": CLASS_NAMES}


if __name__ == "__main__":
    import argparse
    import time

    parser = argparse.ArgumentParser(description="Smoke test del classificatore fuso.")
    parser.add_argument("--model", default="shl_har_fused.keras")
    parser.add_argument("--n-windows", type=int, nargs="+", default=[579, 1060, 141, 2048])
    args = parser.parse_args()

    clf = HARClassifier(args.model)
    rng = np.random.default_rng(0)

    for n in args.n_windows:
        windows = rng.standard_normal((n, 500, 6)).astype(np.float32)
        t0 = time.perf_counter()
        result = clf.predict(windows)
        dt = (time.perf_counter() - t0) * 1000
        print(f"{n:5d} finestre -> {dt:7.1f} ms")
