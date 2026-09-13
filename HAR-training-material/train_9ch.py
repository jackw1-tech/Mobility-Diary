#!/usr/bin/env python3
"""
Train the 9-channel, 5-class CNN with focal loss and the proper protocol.

  trainfit  -> training
  traines   -> early stopping (temporal held-out block from train)
  val       -> official SHL validation, honest final evaluation

Focal loss with class-balanced alpha addresses the heavy class imbalance
(MOVING_VEHICLE ~ half the data) and focuses learning on hard, rare examples
(RUNNING, BIKING). Clipping inside the loss also prevents the NaN loss seen in
the earlier runs.

The ordered validation predictions are saved so the temporal model / smoothing
stage can reuse them.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import tensorflow as tf
from tensorflow.keras.callbacks import EarlyStopping, ModelCheckpoint
from tensorflow.keras.layers import Conv1D, Dense, Dropout, Flatten, Input, MaxPooling1D
from tensorflow.keras.models import Sequential

from preprocess_shl_9ch_5class import CLASS_NAMES, N_CHANNELS, WINDOW_SIZE
from train_cnn1d_har import confusion_matrix, classification_metrics

INPUT_SHAPE = (WINDOW_SIZE, N_CHANNELS)


def load(split: str, data_dir: Path, prefix: str):
    X = np.load(data_dir / f"{prefix}_{split}_X.npy", mmap_mode="r")
    y = np.load(data_dir / f"{prefix}_{split}_y.npy")
    return X, y


def build_model(num_classes: int) -> tf.keras.Model:
    return Sequential([
        Input(shape=INPUT_SHAPE),
        Conv1D(64, 10, activation="relu"),
        MaxPooling1D(2),
        Conv1D(128, 10, activation="relu"),
        MaxPooling1D(2),
        Flatten(),
        Dense(128, activation="relu"),
        Dropout(0.5),
        Dense(num_classes, activation="softmax"),
    ])


def make_focal_loss(alpha: np.ndarray, gamma: float = 2.0):
    """Sparse categorical focal loss with per-class alpha weighting."""
    alpha_t = tf.constant(alpha, dtype=tf.float32)

    def loss(y_true, y_pred):
        y_true = tf.cast(tf.reshape(y_true, [-1]), tf.int32)
        y_pred = tf.clip_by_value(y_pred, 1e-7, 1.0 - 1e-7)
        p_t = tf.gather(y_pred, y_true, batch_dims=1)
        a_t = tf.gather(alpha_t, y_true)
        return tf.reduce_mean(a_t * tf.pow(1.0 - p_t, gamma) * (-tf.math.log(p_t)))

    return loss


def balanced_alpha(y: np.ndarray, num_classes: int) -> np.ndarray:
    counts = np.bincount(y.astype(np.int64), minlength=num_classes)
    total = counts.sum()
    alpha = total / (num_classes * np.maximum(counts, 1))
    return (alpha / alpha.mean()).astype(np.float32)  # normalized around 1


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Train 9-channel 5-class CNN with focal loss.")
    p.add_argument("--data-dir", type=Path, default=Path("processed_9ch"))
    p.add_argument("--prefix", default="shl_9ch_5class")
    p.add_argument("--out-dir", type=Path, default=Path("models_9ch"))
    p.add_argument("--epochs", type=int, default=25)
    p.add_argument("--batch-size", type=int, default=256)
    p.add_argument("--patience", type=int, default=5)
    p.add_argument("--gamma", type=float, default=2.0)
    p.add_argument("--seed", type=int, default=42)
    return p.parse_args()


def main() -> None:
    args = parse_args()
    tf.keras.utils.set_random_seed(args.seed)
    args.out_dir.mkdir(parents=True, exist_ok=True)
    num_classes = len(CLASS_NAMES)

    X_fit, y_fit = load("trainfit", args.data_dir, args.prefix)
    X_es, y_es = load("traines", args.data_dir, args.prefix)
    X_val, y_val = load("val", args.data_dir, args.prefix)
    print(f"trainfit: {X_fit.shape}  traines: {X_es.shape}  val: {X_val.shape}")

    alpha = balanced_alpha(y_fit, num_classes)
    print(f"focal alpha (per class): {np.round(alpha, 3)}  gamma={args.gamma}")

    model = build_model(num_classes)
    model.compile(optimizer="adam", loss=make_focal_loss(alpha, args.gamma), metrics=["accuracy"])
    model.summary()

    best_path = args.out_dir / f"{args.prefix}_best.keras"
    callbacks = [
        EarlyStopping(monitor="val_accuracy", patience=args.patience, restore_best_weights=True),
        ModelCheckpoint(best_path, monitor="val_accuracy", save_best_only=True),
    ]

    print("\nTraining...")
    history = model.fit(
        X_fit, y_fit,
        epochs=args.epochs, batch_size=args.batch_size,
        validation_data=(X_es, y_es),
        callbacks=callbacks, shuffle=True,
    )
    (args.out_dir / f"{args.prefix}_history.json").write_text(json.dumps(history.history))

    print("\nEvaluating on official validation...")
    probs = model.predict(X_val, batch_size=args.batch_size, verbose=1)
    y_pred = np.argmax(probs, axis=1)
    np.save(args.out_dir / f"{args.prefix}_val_pred.npy", y_pred)

    matrix = confusion_matrix(y_val, y_pred, num_classes)
    metrics = classification_metrics(matrix, CLASS_NAMES)
    print("\n=== HONEST metrics on official validation (9-channel + focal) ===")
    print(json.dumps(metrics, indent=2))
    print("\nConfusion matrix:")
    print(matrix)

    model.save(args.out_dir / f"{args.prefix}_final.keras")
    np.save(args.out_dir / f"{args.prefix}_confusion_matrix.npy", matrix)
    (args.out_dir / f"{args.prefix}_val_metrics.json").write_text(json.dumps(metrics, indent=2))
    print(f"\nSaved model + metrics to {args.out_dir}")


if __name__ == "__main__":
    main()
