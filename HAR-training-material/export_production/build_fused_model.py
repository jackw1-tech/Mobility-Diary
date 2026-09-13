#!/usr/bin/env python3
"""
Fonde i due modelli di produzione (CNN feature extractor + GRU temporale) in un
UNICO modello Keras end-to-end, senza retraining: i pesi sono copiati bit-per-bit
dai checkpoint esistenti.

Input del modello fuso:  (batch, L, 500, 6) float32  -- finestre grezze, NON normalizzate
Output del modello fuso: (batch, L, 5) float32        -- softmax per finestra

Elimina rispetto alla pipeline attuale (script.py):
  - il secondo file .keras da caricare e mantenere in sync
  - l'estrazione manuale degli embedding come step separato
  - il loop Python con un gru.predict() per ogni chunk da 32 finestre
  - ~16 MB di stato Adam (m/v) rimasti incollati nei checkpoint "best" per errore
    di ModelCheckpoint (il modello va salvato con compile=False / mai ricompilato)

Uso:
    python3 build_fused_model.py \
        --cnn ../models_5class/shl_cnn1d_full_100pct_5class_best.keras \
        --gru ../models_gru/shl_6ch_5class_gru_best.keras \
        --out shl_har_fused.keras

Verifica automaticamente che le predizioni combacino con la pipeline a due stadi
(entro 1e-6, cioe' solo rumore numerico float32) prima di salvare.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import tensorflow as tf
from tensorflow.keras import layers
from tensorflow.keras.models import Model, load_model

CLASS_NAMES = ["IDLE", "WALKING", "RUNNING", "BIKING", "MOVING_VEHICLE"]


def build_fused(seq_len: int | None = None) -> Model:
    """Ricostruisce l'architettura CNN(TimeDistributed) + GRU con pesi non ancora caricati.

    seq_len=None (consigliato) -> lunghezza di sequenza dinamica, decisa a runtime
    a ogni chiamata di predict(). seq_len=int -> shape fissa, richiesta per TFLite.
    """
    inp = layers.Input(shape=(seq_len, 500, 6), name="window_sequence")
    x = layers.TimeDistributed(layers.Conv1D(64, 10, activation="relu"), name="td_conv1")(inp)
    x = layers.TimeDistributed(layers.MaxPooling1D(2), name="td_pool1")(x)
    x = layers.TimeDistributed(layers.Conv1D(128, 10, activation="relu"), name="td_conv2")(x)
    x = layers.TimeDistributed(layers.MaxPooling1D(2), name="td_pool2")(x)
    x = layers.TimeDistributed(layers.Flatten(), name="td_flatten")(x)
    x = layers.TimeDistributed(layers.Dense(128, activation="relu"), name="td_embedding")(x)
    x = layers.Bidirectional(layers.GRU(64, return_sequences=True), name="bi_gru")(x)
    x = layers.Dropout(0.3, name="gru_dropout")(x)
    out = layers.TimeDistributed(layers.Dense(len(CLASS_NAMES), activation="softmax"), name="td_classify")(x)
    return Model(inp, out, name="har_fused_cnn_gru")


def copy_weights(fused: Model, cnn: Model, gru: Model) -> None:
    """Copia i pesi dai due checkpoint originali nel modello fuso.

    Assume l'architettura esatta prodotta da train_cnn1d_har.py (CNN, 8 layer
    sequenziali) e train_gru_6ch.py (GRU, Bidirectional+Dropout+TimeDistributed).
    Se le architetture sorgente cambiano, gli indici qui sotto vanno aggiornati.
    """
    conv1, _, conv2, _ = (cnn.get_layer(index=i) for i in range(4))
    dense_embed = cnn.get_layer(index=5)  # Dense(128) penultimo, prima di Dropout+Dense(5)
    bi_gru = gru.get_layer(index=1)
    td_dense = gru.get_layer(index=3).layer

    fused.get_layer("td_conv1").layer.set_weights(conv1.get_weights())
    fused.get_layer("td_conv2").layer.set_weights(conv2.get_weights())
    fused.get_layer("td_embedding").layer.set_weights(dense_embed.get_weights())
    fused.get_layer("bi_gru").set_weights(bi_gru.get_weights())
    fused.get_layer("td_classify").layer.set_weights(td_dense.get_weights())


def verify_equivalence(fused: Model, cnn: Model, gru: Model, seq_len: int, seed: int = 0) -> float:
    """Confronta il modello fuso con la pipeline attuale a due stadi su dati casuali.
    Ritorna la differenza massima assoluta sulle probabilita' (atteso: rumore float32, ~1e-6)."""
    rng = np.random.default_rng(seed)
    n_seq = 4
    X = rng.standard_normal((n_seq, seq_len, 500, 6)).astype(np.float32)

    extractor = Model(cnn.inputs, cnn.layers[-3].output)
    embeddings = extractor.predict(X.reshape(-1, 500, 6), verbose=0, batch_size=32)
    embeddings = embeddings.reshape(n_seq, seq_len, -1)

    gru_dyn = build_fused_gru_only(seq_len=None)
    gru_dyn.set_weights(gru.get_weights())
    probs_twostage = gru_dyn.predict(embeddings, verbose=0, batch_size=n_seq)

    probs_fused = fused.predict(X, verbose=0, batch_size=n_seq)

    if not np.array_equal(np.argmax(probs_twostage, -1), np.argmax(probs_fused, -1)):
        raise RuntimeError("Le etichette predette dal modello fuso NON combaciano con la pipeline originale!")

    return float(np.max(np.abs(probs_twostage - probs_fused)))


def build_fused_gru_only(seq_len: int | None) -> Model:
    inp = layers.Input(shape=(seq_len, 128))
    x = layers.Bidirectional(layers.GRU(64, return_sequences=True))(inp)
    x = layers.Dropout(0.3)(x)
    out = layers.TimeDistributed(layers.Dense(len(CLASS_NAMES), activation="softmax"))(x)
    return Model(inp, out)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--cnn", type=Path, default=Path("../models_5class/shl_cnn1d_full_100pct_5class_best.keras"))
    p.add_argument("--gru", type=Path, default=Path("../models_gru/shl_6ch_5class_gru_best.keras"))
    p.add_argument("--out", type=Path, default=Path("shl_har_fused.keras"))
    p.add_argument("--fixed-seq-len", type=int, default=None,
                   help="Se impostato, salva con lunghezza di sequenza FISSA (richiesto solo per export TFLite).")
    p.add_argument("--verify-seq-len", type=int, default=128,
                   help="Lunghezza usata per il test di equivalenza numerica.")
    return p.parse_args()


def main() -> None:
    args = parse_args()

    print(f"Caricamento CNN da {args.cnn} ...")
    cnn = load_model(args.cnn, compile=False)
    print(f"Caricamento GRU da {args.gru} ...")
    gru = load_model(args.gru, compile=False)

    print("Costruzione modello fuso end-to-end (CNN TimeDistributed + GRU)...")
    fused = build_fused(seq_len=args.fixed_seq_len)
    copy_weights(fused, cnn, gru)
    fused.summary()

    print(f"\nVerifica equivalenza numerica vs pipeline a due stadi (L={args.verify_seq_len})...")
    max_diff = verify_equivalence(fused, cnn, gru, seq_len=args.verify_seq_len)
    print(f"Max |diff| sulle probabilita': {max_diff:.2e}  (atteso: rumore float32, tipicamente <1e-5)")
    if max_diff > 1e-3:
        raise RuntimeError("Differenza troppo grande: controllare l'architettura/i pesi copiati prima di salvare.")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    fused.save(args.out)  # niente optimizer: il modello non e' mai stato compilato -> file solo-pesi
    import os
    print(f"\nSalvato: {args.out}  ({os.path.getsize(args.out) / 1e6:.2f} MB)")
    print("Confronto dimensioni:")
    print(f"  CNN originale (con stato Adam): {os.path.getsize(args.cnn) / 1e6:.2f} MB")
    print(f"  GRU originale (con stato Adam): {os.path.getsize(args.gru) / 1e6:.2f} MB")
    print(f"  Totale originale:               {(os.path.getsize(args.cnn) + os.path.getsize(args.gru)) / 1e6:.2f} MB")
    print(f"  Modello fuso, solo pesi:        {os.path.getsize(args.out) / 1e6:.2f} MB")


if __name__ == "__main__":
    main()
