#!/usr/bin/env python3

from __future__ import annotations

import math

import numpy as np
import tensorflow as tf

CLASS_NAMES = ["IDLE", "WALKING", "RUNNING", "BIKING", "MOVING_VEHICLE"]
DEFAULT_SEQ_LEN = 128


class HARClassifier:
    def __init__(self, model_path: str, seq_len: int = DEFAULT_SEQ_LEN):
        self.model = tf.keras.models.load_model(model_path, compile=False)
        self.seq_len = seq_len
        self._infer = tf.function(
            lambda x: self.model(x, training=False),
            input_signature=[tf.TensorSpec(shape=[None, seq_len, 500, 6], dtype=tf.float32)],
        )
        
        #Eseguita subito con dati nulli per compilare subito il modello
        self._infer(tf.zeros((1, seq_len, 500, 6), dtype=tf.float32))

    #vera funzione che classifica
    def predict(self, windows: np.ndarray) -> dict:
        windows = np.asarray(windows, dtype=np.float32)
        if windows.ndim != 3 or windows.shape[1:] != (500, 6):
            raise ValueError(f"Shape attesa (N, 500, 6), ricevuta {windows.shape}")

        n = windows.shape[0]
        # Ho n finestre da 500 x 6 -> calcolo quante sequenze da seq_len finestre servono
        n_seq = math.ceil(n / self.seq_len)
        # calcolo quante finestre vuote rimangono per avere solo sequenze piene
        pad = n_seq * self.seq_len - n
        #creo finestre di soli zeri
        if pad:
            windows = np.concatenate([windows, np.zeros((pad, 500, 6), np.float32)])

        # (N+pad, 500, 6) -> [(128,500,6), (128,500,6), ...] -> (n_seq, 128, 500, 6)
        sequences = windows.reshape(n_seq, self.seq_len, 500, 6)

        #Converto in tensore e chiamo il modello, converte il tensore in output in numpy
        #Output: (n_seq, 128, 5) -> per ogni sequenza, per ogni finestra, le 5 probabilità di classe
        probs = self._infer(tf.constant(sequences)).numpy()

        # (n_seq, 128, 5) -> (128 * n sqeq, 5)
        probs = probs.reshape(n_seq * self.seq_len, len(CLASS_NAMES))[:n] #taglia le ultime finestre di padding
        
        #Prendo solo la probabilità più alta
        labels = np.argmax(probs, axis=-1)

        return {"labels": labels, "probs": probs, "classes": CLASS_NAMES}
