#!/usr/bin/env python3
"""Confusion matrix and classification metrics."""

from __future__ import annotations

import numpy as np


def confusion_matrix(y_true: np.ndarray, y_pred: np.ndarray, num_classes: int) -> np.ndarray:
    matrix = np.zeros((num_classes, num_classes), dtype=np.int64)
    np.add.at(matrix, (y_true.astype(np.int64), y_pred.astype(np.int64)), 1)
    return matrix


def classification_metrics(matrix: np.ndarray, class_names: dict[int, str]) -> dict[str, object]:
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
