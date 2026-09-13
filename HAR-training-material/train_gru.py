#!/usr/bin/env python3
"""
Fase B: temporal context via a GRU on top of the trained 9-channel CNN.

Two-stage design (cheap and tractable):
  1. Use the trained CNN as a frozen feature extractor: each 5s window -> a
     128-dim embedding (the penultimate Dense(128) activation).
  2. Train a bidirectional GRU that reads sequences of consecutive embeddings
     (in chronological order, within each position) and labels every window
     using past AND future context -- the learned analogue of smoothing.

Sequence length L=64 windows ~= 320s, matching the smoothing sweet spot.
Evaluation is on the official SHL validation -> honest number.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import tensorflow as tf
from tensorflow.keras.layers import GRU, Bidirectional, Dense, Dropout, Input, TimeDistributed
from tensorflow.keras.models import Model

from preprocess_shl_9ch_5class import CLASS_NAMES
from train_cnn1d_har import confusion_matrix, classification_metrics
from train_9ch import balanced_alpha


def load_split(data_dir: Path, prefix: str, split: str):
    X = np.load(data_dir / f"{prefix}_{split}_X.npy", mmap_mode="r")
    y = np.load(data_dir / f"{prefix}_{split}_y.npy")
    return X, y


def embedding_extractor(cnn: tf.keras.Model) -> tf.keras.Model:
    """Sub-model from input to the penultimate Dense(128) activation."""
    return Model(cnn.inputs, cnn.layers[-3].output)  # Dense(128) -> Dropout -> Dense(5)


def embed(extractor: tf.keras.Model, X, batch_size: int) -> np.ndarray:
    return extractor.predict(X, batch_size=batch_size, verbose=1).astype(np.float32)


def make_train_sequences(emb, y, blocks, L, stride):
    """Overlapping sequences within each position block (for training/es)."""
    xs, ys = [], []
    for s, e in blocks:
        n = e - s
        for i in range(0, max(1, n - L + 1), stride):
            seg_x = emb[s + i: s + i + L]
            seg_y = y[s + i: s + i + L]
            if len(seg_x) < L:  # pad tail
                pad = L - len(seg_x)
                seg_x = np.concatenate([seg_x, np.zeros((pad, emb.shape[1]), emb.dtype)])
                seg_y = np.concatenate([seg_y, np.zeros(pad, y.dtype)])
            xs.append(seg_x)
            ys.append(seg_y)
    return np.asarray(xs), np.asarray(ys)


def make_eval_sequences(emb, blocks, L):
    """Non-overlapping sequences covering each block, with metadata to scatter back."""
    xs, meta = [], []  # meta: (global_start, valid_len)
    for s, e in blocks:
        n = e - s
        for i in range(0, n, L):
            seg = emb[s + i: s + i + L]
            valid = len(seg)
            if valid < L:
                seg = np.concatenate([seg, np.zeros((L - valid, emb.shape[1]), emb.dtype)])
            xs.append(seg)
            meta.append((s + i, valid))
    return np.asarray(xs), meta


def sequence_focal_loss(alpha, gamma=2.0):
    alpha_t = tf.constant(alpha, dtype=tf.float32)

    def loss(y_true, y_pred):
        y_true = tf.cast(tf.reshape(y_true, [-1]), tf.int32)
        y_pred = tf.clip_by_value(tf.reshape(y_pred, [-1, tf.shape(y_pred)[-1]]), 1e-7, 1 - 1e-7)
        p_t = tf.gather(y_pred, y_true, batch_dims=1)
        a_t = tf.gather(alpha_t, y_true)
        return tf.reduce_mean(a_t * tf.pow(1.0 - p_t, gamma) * (-tf.math.log(p_t)))

    return loss


def build_gru(L, emb_dim, num_classes, units=64):
    inp = Input(shape=(L, emb_dim))
    x = Bidirectional(GRU(units, return_sequences=True))(inp)
    x = Dropout(0.3)(x)
    out = TimeDistributed(Dense(num_classes, activation="softmax"))(x)
    return Model(inp, out)


def parse_args():
    p = argparse.ArgumentParser(description="Train a GRU temporal head on CNN embeddings.")
    p.add_argument("--data-dir", type=Path, default=Path("processed_9ch"))
    p.add_argument("--prefix", default="shl_9ch_5class")
    p.add_argument("--cnn", type=Path, default=Path("models_9ch/shl_9ch_5class_best.keras"))
    p.add_argument("--out-dir", type=Path, default=Path("models_gru"))
    p.add_argument("--seq-len", type=int, default=64)
    p.add_argument("--epochs", type=int, default=30)
    p.add_argument("--batch-size", type=int, default=64)
    p.add_argument("--patience", type=int, default=6)
    p.add_argument("--seed", type=int, default=42)
    return p.parse_args()


def main():
    args = parse_args()
    tf.keras.utils.set_random_seed(args.seed)
    args.out_dir.mkdir(parents=True, exist_ok=True)
    num_classes = len(CLASS_NAMES)
    L = args.seq_len

    meta = json.loads((args.data_dir / f"{args.prefix}_meta.json").read_text())
    fit_blocks = meta["train_position_boundaries"]["trainfit"]
    es_blocks = meta["train_position_boundaries"]["traines"]
    val_blocks = [[s, e] for s, e, _ in meta["val_position_boundaries"]]

    print("Loading CNN and building embedding extractor...")
    cnn = tf.keras.models.load_model(args.cnn, compile=False)
    extractor = embedding_extractor(cnn)
    print(f"embedding dim = {extractor.output_shape[-1]}")

    X_fit, y_fit = load_split(args.data_dir, args.prefix, "trainfit")
    X_es, y_es = load_split(args.data_dir, args.prefix, "traines")
    X_val, y_val = load_split(args.data_dir, args.prefix, "val")

    print("Extracting embeddings...")
    emb_fit = embed(extractor, X_fit, args.batch_size * 4)
    emb_es = embed(extractor, X_es, args.batch_size * 4)
    emb_val = embed(extractor, X_val, args.batch_size * 4)
    emb_dim = emb_fit.shape[1]

    print("Building sequences...")
    Xtr, ytr = make_train_sequences(emb_fit, y_fit, fit_blocks, L, stride=L // 2)
    Xes, yes = make_train_sequences(emb_es, y_es, es_blocks, L, stride=L)
    print(f"train seqs={Xtr.shape}  es seqs={Xes.shape}")

    alpha = balanced_alpha(y_fit, num_classes)
    model = build_gru(L, emb_dim, num_classes)
    model.compile(optimizer="adam", loss=sequence_focal_loss(alpha), metrics=["accuracy"])
    model.summary()

    callbacks = [
        tf.keras.callbacks.EarlyStopping(monitor="val_accuracy", patience=args.patience, restore_best_weights=True),
        tf.keras.callbacks.ModelCheckpoint(args.out_dir / f"{args.prefix}_gru_best.keras",
                                           monitor="val_accuracy", save_best_only=True),
    ]
    print("\nTraining GRU...")
    model.fit(Xtr, ytr, validation_data=(Xes, yes), epochs=args.epochs,
              batch_size=args.batch_size, callbacks=callbacks, shuffle=True)

    print("\nEvaluating on official validation...")
    Xev, ev_meta = make_eval_sequences(emb_val, val_blocks, L)
    probs = model.predict(Xev, batch_size=args.batch_size, verbose=1)  # (num_seq, L, C)
    seq_pred = np.argmax(probs, axis=-1)

    y_pred = np.empty(len(y_val), dtype=np.int64)
    for (gstart, valid), row in zip(ev_meta, seq_pred):
        y_pred[gstart:gstart + valid] = row[:valid]

    np.save(args.out_dir / f"{args.prefix}_gru_val_pred.npy", y_pred)
    matrix = confusion_matrix(y_val, y_pred, num_classes)
    metrics = classification_metrics(matrix, CLASS_NAMES)
    print("\n=== HONEST metrics on official validation (CNN + GRU) ===")
    print(json.dumps(metrics, indent=2))
    print("\nConfusion matrix:")
    print(matrix)

    (args.out_dir / f"{args.prefix}_gru_val_metrics.json").write_text(json.dumps(metrics, indent=2))
    np.save(args.out_dir / f"{args.prefix}_gru_confusion_matrix.npy", matrix)
    print(f"\nSaved to {args.out_dir}")


if __name__ == "__main__":
    main()
