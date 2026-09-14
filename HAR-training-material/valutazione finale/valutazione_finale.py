
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

import numpy as np
import tensorflow as tf

# metrics.py e' condiviso al livello superiore.
REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from metrics import classification_metrics, confusion_matrix


CLASS_NAMES = {
    0: "IDLE",
    1: "WALKING",
    2: "RUNNING",
    3: "BIKING",
    4: "MOVING_VEHICLE",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as model_file:
        for chunk in iter(lambda: model_file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


PROCESSED_DIR = REPO_ROOT / "processed_6ch"
DATA_PREFIX = "shl_6ch_5class"
TEST_X = PROCESSED_DIR / f"{DATA_PREFIX}_test_X.npy"
TEST_Y = PROCESSED_DIR / f"{DATA_PREFIX}_test_y.npy"
METADATA_PATH = PROCESSED_DIR / f"{DATA_PREFIX}_meta.json"
NORMALIZATION_PATH = PROCESSED_DIR / f"{DATA_PREFIX}_norm_stats.json"
MODEL_PATH = REPO_ROOT / "GRU+CNN" / "shl_har_fused.keras"
OUT_DIR = Path(__file__).resolve().parent
SEQUENCE_LENGTH = 128
BATCH_SIZE = 8


def predict_position(
    model: tf.keras.Model,
    normalized: np.ndarray,
    mean: np.ndarray,
    std: np.ndarray,
    sequence_length: int,
    batch_size: int,
) -> np.ndarray:
    raw = normalized * std + mean
    raw = np.asarray(raw, dtype=np.float32)
    valid = raw.shape[0]
    sequence_count = (valid + sequence_length - 1) // sequence_length
    padded_count = sequence_count * sequence_length
    if padded_count != valid:
        raw = np.pad(raw, ((0, padded_count - valid), (0, 0), (0, 0)))
    sequences = raw.reshape(sequence_count, sequence_length, 500, 6)
    probabilities = model.predict(sequences, batch_size=batch_size, verbose=1)
    return np.argmax(probabilities.reshape(-1, len(CLASS_NAMES))[:valid], axis=1)


def main() -> None:
    x = np.load(TEST_X, mmap_mode="r")
    y = np.load(TEST_Y)
    metadata = json.loads(METADATA_PATH.read_text(encoding="utf-8"))
    normalization = json.loads(NORMALIZATION_PATH.read_text(encoding="utf-8"))
    mean = np.asarray(normalization["mean"], dtype=np.float32)
    std = np.asarray(normalization["std"], dtype=np.float32)
    boundaries = metadata["test_position_boundaries"]

    if x.shape != (len(y), 500, 6):
        raise ValueError(f"Unexpected test set shapes: X={x.shape}, y={y.shape}")

    model = tf.keras.models.load_model(MODEL_PATH, compile=False)
    predictions = np.empty(len(y), dtype=np.int64)
    for start, end, position in boundaries:
        print(f"Evaluating {position}: windows [{start}, {end})")
        predictions[start:end] = predict_position(
            model,
            x[start:end],
            mean,
            std,
            SEQUENCE_LENGTH,
            BATCH_SIZE,
        )

    matrix = confusion_matrix(y, predictions, len(CLASS_NAMES))
    metrics = classification_metrics(matrix, CLASS_NAMES)
    metrics["model_file"] = MODEL_PATH.name
    metrics["model_sha256"] = sha256(MODEL_PATH)
    metrics["sequence_length"] = SEQUENCE_LENGTH
    metrics["validation_windows"] = int(len(y))
    metrics["position_boundaries_preserved"] = True

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    np.save(OUT_DIR / "valutazione_finale_confusion_matrix.npy", matrix)
    np.save(OUT_DIR / "valutazione_finale_predictions.npy", predictions)
    (OUT_DIR / "valutazione_finale.json").write_text(
        json.dumps(metrics, indent=2),
        encoding="utf-8",
    )

    print("\nMetrics:")
    print(json.dumps(metrics, indent=2))
    print("\nConfusion matrix (rows=true, columns=predicted):")
    print(matrix)


if __name__ == "__main__":
    main()
