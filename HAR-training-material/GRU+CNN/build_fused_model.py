#!/usr/bin/env python3
"""Fusione dei due modelli"""
from __future__ import annotations

from pathlib import Path

import numpy as np
import tensorflow as tf
from tensorflow.keras import layers
from tensorflow.keras.models import Model, load_model

REPO_ROOT = Path(__file__).resolve().parent.parent

CLASS_NAMES = ["IDLE", "WALKING", "RUNNING", "BIKING", "MOVING_VEHICLE"]


#Struttura CNN + GRU
def build_fused(seq_len: int | None = None) -> Model:
    #(128, 500, 6)
    inp = layers.Input(shape=(seq_len, 500, 6), name="window_sequence")
    #(128, 491, 64)
    x = layers.TimeDistributed(layers.Conv1D(64, 10, activation="relu"), name="td_conv1")(inp)
    #(128, 245, 64)
    x = layers.TimeDistributed(layers.MaxPooling1D(2), name="td_pool1")(x)
    #(128, 236, 128)
    x = layers.TimeDistributed(layers.Conv1D(128, 10, activation="relu"), name="td_conv2")(x)
    #(128, 118, 128)
    x = layers.TimeDistributed(layers.MaxPooling1D(2), name="td_pool2")(x)
    #(128, 15104)
    x = layers.TimeDistributed(layers.Flatten(), name="td_flatten")(x)
    #(128, 128)
    x = layers.TimeDistributed(layers.Dense(128, activation="relu"), name="td_embedding")(x)
    #GRU
    x = layers.Bidirectional(layers.GRU(64, return_sequences=True), name="bi_gru")(x)
    x = layers.Dropout(0.3, name="gru_dropout")(x)
    out = layers.TimeDistributed(layers.Dense(len(CLASS_NAMES), activation="softmax"), name="td_classify")(x)
    return Model(inp, out, name="har_fused_cnn_gru")


def copy_weights(fused: Model, cnn: Model, gru: Model) -> None:
    conv1, _, conv2, _ = (cnn.get_layer(index=i) for i in range(4))
    dense_embed = cnn.get_layer(index=5)  # Dense(128) penultimo, prima di Dropout+Dense(5)
    bi_gru = gru.get_layer(index=1)
    td_dense = gru.get_layer(index=3).layer

    fused.get_layer("td_conv1").layer.set_weights(conv1.get_weights())
    fused.get_layer("td_conv2").layer.set_weights(conv2.get_weights())
    fused.get_layer("td_embedding").layer.set_weights(dense_embed.get_weights())
    fused.get_layer("bi_gru").set_weights(bi_gru.get_weights())
    fused.get_layer("td_classify").layer.set_weights(td_dense.get_weights())


def build_fused_gru_only(seq_len: int | None) -> Model:
    inp = layers.Input(shape=(seq_len, 128))
    x = layers.Bidirectional(layers.GRU(64, return_sequences=True))(inp)
    x = layers.Dropout(0.3)(x)
    out = layers.TimeDistributed(layers.Dense(len(CLASS_NAMES), activation="softmax"))(x)
    return Model(inp, out)


CNN_PATH = REPO_ROOT / "cnn 1d" / "models_5class" / "shl_cnn1d_full_100pct_5class_best.keras"
GRU_PATH = REPO_ROOT / "GRU" / "models_gru" / "shl_6ch_5class_gru_best.keras"
OUT_PATH = Path(__file__).resolve().parent / "shl_har_fused.keras"
FIXED_SEQ_LEN = None #Dimensione variabile


def main() -> None:
    cnn = load_model(CNN_PATH, compile=False)
    gru = load_model(GRU_PATH, compile=False)

    fused = build_fused(seq_len=FIXED_SEQ_LEN)
    copy_weights(fused, cnn, gru)
    fused.summary()
    
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    fused.save(OUT_PATH) 

if __name__ == "__main__":
    main()
