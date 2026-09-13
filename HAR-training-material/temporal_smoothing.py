#!/usr/bin/env python3
"""
Temporal smoothing (majority-vote sliding window) on top of the trained model's
predictions on the official SHL validation set.

The model classifies each 5s window independently, so isolated misclassifications
(e.g. a stopped vehicle predicted as IDLE) can be corrected using neighbouring
predictions. Smoothing is applied WITHIN each phone position separately, never
across position boundaries (they are independent recordings).

Each validation position holds 28789 chronological windows; the saved
OFFICIALVAL arrays concatenate them in order: Bag, Hand, Hips, Torso.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import tensorflow as tf

from preprocess_shl_cnn1d_5class import CLASS_NAMES
from train_cnn1d_har import confusion_matrix, classification_metrics

POSITION_ORDER = ("Bag", "Hand", "Hips", "Torso")
WINDOWS_PER_POSITION = 28789  # rows per validation position


def majority_filter(preds: np.ndarray, window: int, num_classes: int) -> np.ndarray:
    """Sliding-window majority vote. window must be odd; window=1 is a no-op."""
    if window <= 1:
        return preds.copy()
    k = window // 2
    n = preds.size
    out = np.empty_like(preds)
    for i in range(n):
        lo = max(0, i - k)
        hi = min(n, i + k + 1)
        counts = np.bincount(preds[lo:hi], minlength=num_classes)
        out[i] = counts.argmax()
    return out


def smooth_per_position(preds: np.ndarray, window: int, num_classes: int,
                        block_size: int = WINDOWS_PER_POSITION) -> np.ndarray:
    """Apply the majority filter independently inside each position block."""
    out = np.empty_like(preds)
    for start in range(0, preds.size, block_size):
        end = min(preds.size, start + block_size)
        out[start:end] = majority_filter(preds[start:end], window, num_classes)
    return out


def idle_move_errors(matrix: np.ndarray, idle: int = 0, move: int = 4) -> int:
    """Count errors on the IDLE <-> MOVING_VEHICLE axis."""
    return int(matrix[idle, move] + matrix[move, idle])


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Temporal smoothing on validation predictions.")
    parser.add_argument("--x", type=Path, default=Path("models_5class/shl_cnn1d_full_100pct_5class_OFFICIALVAL_X.npy"))
    parser.add_argument("--y", type=Path, default=Path("models_5class/shl_cnn1d_full_100pct_5class_OFFICIALVAL_y.npy"))
    parser.add_argument("--model", type=Path, default=Path("models_5class/shl_cnn1d_full_100pct_5class_best.keras"))
    parser.add_argument("--batch-size", type=int, default=256)
    parser.add_argument("--windows", type=int, nargs="+", default=[1, 3, 5, 9, 15, 31, 61])
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    num_classes = len(CLASS_NAMES)

    X = np.load(args.x, mmap_mode="r")
    y = np.load(args.y)
    print(f"Validation: X={X.shape}, y={y.shape}")

    print(f"Loading model {args.model} ...")
    model = tf.keras.models.load_model(args.model)
    print("Predicting...")
    probs = model.predict(X, batch_size=args.batch_size, verbose=1)
    y_pred_raw = np.argmax(probs, axis=1)

    print("\nwindow | seconds |  accuracy | IDLE<->MOVE errors")
    print("-------+---------+-----------+-------------------")
    results = {}
    for w in args.windows:
        y_pred = smooth_per_position(y_pred_raw, w, num_classes)
        acc = float(np.mean(y_pred == y))
        matrix = confusion_matrix(y, y_pred, num_classes)
        im_err = idle_move_errors(matrix)
        results[w] = {"accuracy": acc, "idle_move_errors": im_err}
        print(f"{w:6d} | {w*5:6d}s | {acc:8.4f}  | {im_err:,}")

    best_w = max(results, key=lambda k: results[k]["accuracy"])
    print(f"\nBest window: {best_w} ({best_w*5}s) -> accuracy {results[best_w]['accuracy']:.4f}")

    # Full report for the best window vs baseline.
    y_best = smooth_per_position(y_pred_raw, best_w, num_classes)
    matrix_raw = confusion_matrix(y, y_pred_raw, num_classes)
    matrix_best = confusion_matrix(y, y_best, num_classes)

    print("\n=== BASELINE (no smoothing) ===")
    print(f"accuracy={np.mean(y_pred_raw == y):.4f}")
    print(matrix_raw)
    print(json.dumps(classification_metrics(matrix_raw, CLASS_NAMES), indent=2))

    print(f"\n=== SMOOTHED (window={best_w}, {best_w*5}s) ===")
    print(f"accuracy={np.mean(y_best == y):.4f}")
    print(matrix_best)
    print(json.dumps(classification_metrics(matrix_best, CLASS_NAMES), indent=2))


if __name__ == "__main__":
    main()
