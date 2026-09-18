#!/usr/bin/env python3
"""
Alleno una CNN da zero
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
import tensorflow as tf
from tensorflow.keras.callbacks import EarlyStopping, ModelCheckpoint
from tensorflow.keras.layers import Conv1D, Dense, Dropout, Flatten, Input, MaxPooling1D
from tensorflow.keras.models import Sequential


REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from preprocessing import CLASS_NAMES, N_CHANNELS, WINDOW_SIZE
from metrics import confusion_matrix, classification_metrics

INPUT_SHAPE = (WINDOW_SIZE, N_CHANNELS)


def load_split(data_dir: Path, prefix: str, split: str) -> tuple[np.ndarray, np.ndarray]:
    x_path = data_dir / f"{prefix}_{split}_X.npy"
    y_path = data_dir / f"{prefix}_{split}_y.npy"

    if not x_path.exists() or not y_path.exists():
        raise FileNotFoundError(f"Missing split files for '{split}': {x_path.name}, {y_path.name}")

    X = np.load(x_path, mmap_mode="r")
    y = np.load(y_path)

    if X.ndim != 3 or X.shape[1:] != INPUT_SHAPE:
        raise ValueError(f"Unexpected {split} X shape: {X.shape}. Expected (N, {WINDOW_SIZE}, {N_CHANNELS}).")
    if y.ndim != 1 or y.shape[0] != X.shape[0]:
        raise ValueError(f"Unexpected {split} y shape: {y.shape}. Expected ({X.shape[0]},).")

    return X, y


def build_model(input_shape: tuple[int, int], num_classes: int) -> tf.keras.Model:
    model = Sequential(
        [   # 500 x 6
            Input(shape=input_shape),
            # 491 x 64
            Conv1D(filters=64, kernel_size=10, activation="relu"),
            # 245 X 64
            MaxPooling1D(pool_size=2),
            # 236 X 128
            Conv1D(filters=128, kernel_size=10, activation="relu"),
            #118 x 128
            MaxPooling1D(pool_size=2),
            # 15104 x 1
            Flatten(),
            # 128 x 1
            Dense(128, activation="relu"),
            # 128 x 1 con il 50% di zeri
            Dropout(0.5),
            # 5 x 1
            Dense(num_classes, activation="softmax"),
        ]
    )

    model.compile(
        optimizer="adam",
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )
    return model

# Assegna pesi diversi alle classi in base alla loro frequenza nel training set
# Peso * Loss
def compute_class_weights(y_train: np.ndarray, num_classes: int) -> dict[int, float]:
    counts = np.bincount(y_train.astype(np.int64), minlength=num_classes)
    total = counts.sum()
    weights = {}

    for class_id, count in enumerate(counts):
        if count == 0:
            weights[class_id] = 0.0
        else:
            weights[class_id] = float(total / (num_classes * count))

    return weights


def save_json(path: Path, data: object) -> None:
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")


DATA_DIR = REPO_ROOT / "processed_6ch"
DATA_PREFIX = "shl_6ch_5class"
PREFIX = "shl_cnn1d_full_100pct_5class"
OUT_DIR = Path(__file__).resolve().parent / "models_5class"
EPOCHS = 20
BATCH_SIZE = 64
PATIENCE = 4 #Fermati dopo 4 epoche in cui l accuracy non migliora
SEED = 50



def main() -> None:
    tf.keras.utils.set_random_seed(SEED)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    num_classes = len(CLASS_NAMES)
    X_train, y_train = load_split(DATA_DIR, DATA_PREFIX, "train")
    X_val, y_val = load_split(DATA_DIR, DATA_PREFIX, "validation")
    X_test, y_test = load_split(DATA_DIR, DATA_PREFIX, "test")


    
    class_weights = compute_class_weights(y_train, num_classes)
   

    model = build_model(INPUT_SHAPE, num_classes)
    model.summary()

    best_model_path = OUT_DIR / f"{PREFIX}_best.keras"
    final_model_path = OUT_DIR / f"{PREFIX}_final.keras"
    history_path = OUT_DIR / f"{PREFIX}_history.json"
    metrics_path = OUT_DIR / "result_training_cnn_1d.json"
    confusion_path = OUT_DIR / f"{PREFIX}_confusion_matrix.npy"

    callbacks = [
        EarlyStopping(
            monitor="val_accuracy",
            patience=PATIENCE,
            restore_best_weights=True,
        ),
        ModelCheckpoint(
            filepath=best_model_path,
            monitor="val_accuracy",
            save_best_only=True,
        ),
    ]

    # Training vero
    history = model.fit(
        X_train,
        y_train,
        epochs=EPOCHS,
        batch_size=BATCH_SIZE,
        validation_data=(X_val, y_val),
        callbacks=callbacks,
        class_weight=class_weights,
        shuffle=True,
    )

    save_json(history_path, history.history)

   
    test_loss, test_accuracy = model.evaluate(X_test, y_test, batch_size=BATCH_SIZE, verbose=1)
    probabilities = model.predict(X_test, batch_size=BATCH_SIZE, verbose=1)
    y_pred = np.argmax(probabilities, axis=1)

    matrix = confusion_matrix(y_test, y_pred, num_classes)
    metrics = classification_metrics(matrix, CLASS_NAMES)
    metrics["test_loss"] = float(test_loss)
    metrics["test_accuracy_keras"] = float(test_accuracy)
    metrics["confusion_matrix_file"] = confusion_path.name

    model.save(final_model_path)
    np.save(confusion_path, matrix)
    save_json(metrics_path, metrics)


if __name__ == "__main__":
    main()
