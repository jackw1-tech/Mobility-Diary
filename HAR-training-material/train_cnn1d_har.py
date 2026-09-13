#!/usr/bin/env python3
"""
Train a lightweight 1D CNN for SHL/HAR supervised pre-training.

Expected input files are produced by preprocess_shl_cnn1d.py:
  <prefix>_train_X.npy, <prefix>_train_y.npy
  <prefix>_val_X.npy,   <prefix>_val_y.npy
  <prefix>_test_X.npy,  <prefix>_test_y.npy
  <prefix>_label_map.json
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


DEFAULT_PREFIX = "shl_cnn1d_full_100pct_6class"
INPUT_SHAPE = (500, 6)


def load_label_map(path: Path) -> dict[int, str]:
    """Load class names saved by the preprocessing script."""
    if not path.exists():
        return {
            0: "IDLE",
            1: "WALKING",
            2: "RUNNING",
            3: "BIKING",
            4: "DRIVING",
            5: "PUBLIC_TRANSPORT",
        }

    raw = json.loads(path.read_text(encoding="utf-8"))
    return {int(key): value for key, value in raw.items()}


def load_split(data_dir: Path, prefix: str, split: str) -> tuple[np.ndarray, np.ndarray]:
    """Load one split. X is memory-mapped to avoid copying large arrays into RAM."""
    x_path = data_dir / f"{prefix}_{split}_X.npy"
    y_path = data_dir / f"{prefix}_{split}_y.npy"

    if not x_path.exists() or not y_path.exists():
        raise FileNotFoundError(f"Missing split files for '{split}': {x_path.name}, {y_path.name}")

    X = np.load(x_path, mmap_mode="r")
    y = np.load(y_path)

    if X.ndim != 3 or X.shape[1:] != INPUT_SHAPE:
        raise ValueError(f"Unexpected {split} X shape: {X.shape}. Expected (N, 500, 6).")
    if y.ndim != 1 or y.shape[0] != X.shape[0]:
        raise ValueError(f"Unexpected {split} y shape: {y.shape}. Expected ({X.shape[0]},).")

    return X, y


def build_model(input_shape: tuple[int, int], num_classes: int) -> tf.keras.Model:
    """Build the CNN 1D architecture."""
    model = Sequential(
        [
            Input(shape=input_shape),
            Conv1D(filters=64, kernel_size=10, activation="relu"),
            MaxPooling1D(pool_size=2),
            Conv1D(filters=128, kernel_size=10, activation="relu"),
            MaxPooling1D(pool_size=2),
            Flatten(),
            Dense(128, activation="relu"),
            Dropout(0.5),
            Dense(num_classes, activation="softmax"),
        ]
    )

    model.compile(
        optimizer="adam",
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )
    return model


def confusion_matrix(y_true: np.ndarray, y_pred: np.ndarray, num_classes: int) -> np.ndarray:
    """Compute a multiclass confusion matrix without requiring scikit-learn."""
    matrix = np.zeros((num_classes, num_classes), dtype=np.int64)
    np.add.at(matrix, (y_true.astype(np.int64), y_pred.astype(np.int64)), 1)
    return matrix


def classification_metrics(matrix: np.ndarray, class_names: dict[int, str]) -> dict[str, object]:
    """Compute accuracy, precision, recall and F1 from a confusion matrix."""
    support = matrix.sum(axis=1)
    predicted = matrix.sum(axis=0)
    true_positive = np.diag(matrix)

    precision = np.divide(
        true_positive,
        predicted,
        out=np.zeros_like(true_positive, dtype=np.float64),
        where=predicted != 0,
    )
    recall = np.divide(
        true_positive,
        support,
        out=np.zeros_like(true_positive, dtype=np.float64),
        where=support != 0,
    )
    f1 = np.divide(
        2 * precision * recall,
        precision + recall,
        out=np.zeros_like(precision, dtype=np.float64),
        where=(precision + recall) != 0,
    )

    total = matrix.sum()
    accuracy = float(true_positive.sum() / total) if total else 0.0
    weights = support / total if total else np.zeros_like(support, dtype=np.float64)

    per_class = {}
    for class_id in range(matrix.shape[0]):
        per_class[str(class_id)] = {
            "name": class_names.get(class_id, f"class_{class_id}"),
            "support": int(support[class_id]),
            "precision": float(precision[class_id]),
            "recall": float(recall[class_id]),
            "f1": float(f1[class_id]),
        }

    return {
        "accuracy": accuracy,
        "macro_precision": float(np.mean(precision)),
        "macro_recall": float(np.mean(recall)),
        "macro_f1": float(np.mean(f1)),
        "weighted_precision": float(np.sum(precision * weights)),
        "weighted_recall": float(np.sum(recall * weights)),
        "weighted_f1": float(np.sum(f1 * weights)),
        "per_class": per_class,
    }


def compute_class_weights(y_train: np.ndarray, num_classes: int) -> dict[int, float]:
    """
    Compute balanced class weights:
      weight_c = n_samples / (n_classes * n_samples_c)
    This reduces bias toward very frequent classes during training.
    """
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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Train and evaluate a 1D CNN on preprocessed SHL/HAR splits.")
    parser.add_argument("--data-dir", type=Path, default=Path("processed"))
    parser.add_argument("--prefix", default=DEFAULT_PREFIX)
    parser.add_argument("--out-dir", type=Path, default=Path("models"))
    parser.add_argument("--epochs", type=int, default=20)
    parser.add_argument("--batch-size", type=int, default=64)
    parser.add_argument("--patience", type=int, default=4)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument(
        "--no-class-weights",
        action="store_true",
        help="Disable balanced class weights during training.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    tf.keras.utils.set_random_seed(args.seed)
    args.out_dir.mkdir(parents=True, exist_ok=True)

    label_map = load_label_map(args.data_dir / f"{args.prefix}_label_map.json")
    num_classes = len(label_map)

    print("Loading train/val/test splits...")
    X_train, y_train = load_split(args.data_dir, args.prefix, "train")
    X_val, y_val = load_split(args.data_dir, args.prefix, "val")
    X_test, y_test = load_split(args.data_dir, args.prefix, "test")

    print(f"train: X={X_train.shape}, y={y_train.shape}")
    print(f"val:   X={X_val.shape}, y={y_val.shape}")
    print(f"test:  X={X_test.shape}, y={y_test.shape}")
    print(f"classes: {label_map}")

    class_weights = None
    if not args.no_class_weights:
        class_weights = compute_class_weights(y_train, num_classes)
        print(f"class weights: {class_weights}")

    model = build_model(INPUT_SHAPE, num_classes)
    model.summary()

    best_model_path = args.out_dir / f"{args.prefix}_best.keras"
    final_model_path = args.out_dir / f"{args.prefix}_final.keras"
    history_path = args.out_dir / f"{args.prefix}_history.json"
    metrics_path = args.out_dir / f"{args.prefix}_test_metrics.json"
    confusion_path = args.out_dir / f"{args.prefix}_confusion_matrix.npy"

    callbacks = [
        EarlyStopping(
            monitor="val_accuracy",
            patience=args.patience,
            restore_best_weights=True,
        ),
        ModelCheckpoint(
            filepath=best_model_path,
            monitor="val_accuracy",
            save_best_only=True,
        ),
    ]

    print("\nTraining...")
    history = model.fit(
        X_train,
        y_train,
        epochs=args.epochs,
        batch_size=args.batch_size,
        validation_data=(X_val, y_val),
        callbacks=callbacks,
        class_weight=class_weights,
        shuffle=True,
    )

    save_json(history_path, history.history)

    print("\nEvaluating on test split...")
    test_loss, test_accuracy = model.evaluate(X_test, y_test, batch_size=args.batch_size, verbose=1)
    probabilities = model.predict(X_test, batch_size=args.batch_size, verbose=1)
    y_pred = np.argmax(probabilities, axis=1)

    matrix = confusion_matrix(y_test, y_pred, num_classes)
    metrics = classification_metrics(matrix, label_map)
    metrics["test_loss"] = float(test_loss)
    metrics["test_accuracy_keras"] = float(test_accuracy)
    metrics["confusion_matrix_file"] = confusion_path.name

    print("\nTest metrics:")
    print(json.dumps(metrics, indent=2))
    print("\nConfusion matrix:")
    print(matrix)

    model.save(final_model_path)
    np.save(confusion_path, matrix)
    save_json(metrics_path, metrics)

    print(f"\nSaved best model:  {best_model_path}")
    print(f"Saved final model: {final_model_path}")
    print(f"Saved history:     {history_path}")
    print(f"Saved metrics:     {metrics_path}")
    print(f"Saved matrix:      {confusion_path}")


if __name__ == "__main__":
    main()
