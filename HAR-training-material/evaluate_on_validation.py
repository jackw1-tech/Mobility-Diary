#!/usr/bin/env python3
"""
Evaluate the already-trained 5-class model on the OFFICIAL SHL validation set.

No retraining. The model never saw this data, so the resulting accuracy is an
honest, leakage-free number. The validation windows are kept in temporal order
(no shuffle) so the same arrays can later feed temporal smoothing.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import tensorflow as tf

from preprocess_shl_cnn1d_5class import build_dataset, CLASS_NAMES, label_distribution
from train_cnn1d_har import confusion_matrix, classification_metrics


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Evaluate trained 5-class model on official SHL validation.")
    parser.add_argument("--validation-root", type=Path, default=Path("DATASET/validation"))
    parser.add_argument("--model", type=Path, default=Path("models_5class/shl_cnn1d_full_100pct_5class_best.keras"))
    parser.add_argument("--out-dir", type=Path, default=Path("models_5class"))
    parser.add_argument("--prefix", default="shl_cnn1d_full_100pct_5class_OFFICIALVAL")
    parser.add_argument("--batch-size", type=int, default=256)
    parser.add_argument("--save-arrays", action="store_true", help="Also save the ordered validation X/y for later reuse.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    num_classes = len(CLASS_NAMES)

    print(f"Building ordered validation set from {args.validation_root} ...")
    X, y = build_dataset(dataset_root=args.validation_root)
    print(f"Validation: X={X.shape}, y={y.shape}")
    print(f"Label distribution: {label_distribution(y)}")

    if args.save_arrays:
        args.out_dir.mkdir(parents=True, exist_ok=True)
        np.save(args.out_dir / f"{args.prefix}_X.npy", X)
        np.save(args.out_dir / f"{args.prefix}_y.npy", y)
        print(f"Saved ordered arrays to {args.out_dir}")

    print(f"\nLoading model {args.model} ...")
    model = tf.keras.models.load_model(args.model)

    print("Predicting...")
    probabilities = model.predict(X, batch_size=args.batch_size, verbose=1)
    y_pred = np.argmax(probabilities, axis=1)

    matrix = confusion_matrix(y, y_pred, num_classes)
    metrics = classification_metrics(matrix, CLASS_NAMES)

    print("\n=== HONEST metrics on official SHL validation ===")
    print(json.dumps(metrics, indent=2))
    print("\nConfusion matrix (rows=true, cols=pred):")
    print(matrix)

    args.out_dir.mkdir(parents=True, exist_ok=True)
    (args.out_dir / f"{args.prefix}_metrics.json").write_text(json.dumps(metrics, indent=2), encoding="utf-8")
    np.save(args.out_dir / f"{args.prefix}_confusion_matrix.npy", matrix)
    print(f"\nSaved metrics and confusion matrix to {args.out_dir}")


if __name__ == "__main__":
    main()
