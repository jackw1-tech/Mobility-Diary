#!/usr/bin/env python3
"""
Script di PreProcessing
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import numpy.lib.format as npformat
import pandas as pd


SIGNAL_NAMES = (
    "Acc_x", "Acc_y", "Acc_z",
    "Gyr_x", "Gyr_y", "Gyr_z",
)
N_CHANNELS = len(SIGNAL_NAMES)
LABEL_NAME = "Label"
WINDOW_SIZE = 500
CHUNK_SIZE = 8_192
ES_FRAC = 0.15
CLASS_NAMES = {
    0: "IDLE",
    1: "WALKING",
    2: "RUNNING",
    3: "BIKING",
    4: "MOVING_VEHICLE",
}

"""1->0, 2->1, 3->2, 4->3, 5/6/7/8->4."""
def remap_labels(raw: np.ndarray) -> np.ndarray:
    y = np.full(raw.shape, -1, dtype=np.int64)
    y[raw == 1] = 0
    y[raw == 2] = 1
    y[raw == 3] = 2
    y[raw == 4] = 3
    y[np.isin(raw, (5, 6, 7, 8))] = 4
    if np.any(y < 0):
        raise ValueError("")
    return y

#Conta il numero di finestre per classe
def label_distribution(y: np.ndarray) -> dict[str, int]:
    labels, counts = np.unique(y, return_counts=True)
    return {f"{int(l)}:{CLASS_NAMES.get(int(l), '?')}": int(c) for l, c in zip(labels, counts)}


#Quante righe ci sono dentro ad un file
def count_windows(position_dir: Path) -> int:
    with open(position_dir / f"{LABEL_NAME}.txt", "rb") as fh:
        return sum(1 for _ in fh)

#Prende 8.192 righe alla volta e crea le 500 x 6
def iter_window_chunks(position_dir: Path):
    signal_iters = {
        name: pd.read_csv(position_dir / f"{name}.txt", sep=r"\s+", header=None,
                          dtype=np.float32, chunksize=CHUNK_SIZE)
        for name in SIGNAL_NAMES
    }
    label_iter = pd.read_csv(position_dir / f"{LABEL_NAME}.txt", sep=r"\s+", header=None,
                             usecols=[0], dtype=np.int16, chunksize=CHUNK_SIZE)

    for label_chunk in label_iter:
        signal_chunks = {name: next(it) for name, it in signal_iters.items()}
        n_rows = len(label_chunk)
        channels = []
        for name in SIGNAL_NAMES:
            data = signal_chunks[name]
            if len(data) != n_rows or data.shape[1] != WINDOW_SIZE:
                raise ValueError(f"Shape mismatch in {position_dir}/{name}: {data.shape}")
            # aggiungo un array (8192, 500) alla lista — uno per ciascuno dei 6 file
            channels.append(data.to_numpy(dtype=np.float32, copy=False))
        # dopo il ciclo: 6 array (8192, 500) -> un unico tensore (8192, 500, 6)
        x_chunk = np.stack(channels, axis=-1)
        y_chunk = remap_labels(label_chunk.iloc[:, 0].to_numpy(dtype=np.int16, copy=False))
        yield x_chunk, y_chunk


# Prende i dati dalle 4 cartelle di train -> 4 file npy
# 1 -> file npy (train_total, 500, 6) -> training 
# 2 -> file npy (train_total) per le label -> label training
# 3 -> file npy (val_total, 500, 6) -> validation 
# 4 -> file npy (val_total) per le label -> label validation
def build_train(train_dirs: list[Path], out_dir: Path, prefix: str):
    sizes = {d.as_posix(): count_windows(d) for d in train_dirs}
    train_total = sum(r - int(round(r * ES_FRAC)) for r in sizes.values())
    val_total = sum(int(round(r * ES_FRAC)) for r in sizes.values())

    #Alloco i fie npy
    train_X = npformat.open_memmap(out_dir / f"{prefix}_train_X.npy", mode="w+",
                                   dtype=np.float32, shape=(train_total, WINDOW_SIZE, N_CHANNELS))
    val_X = npformat.open_memmap(out_dir / f"{prefix}_validation_X.npy", mode="w+",
                                 dtype=np.float32, shape=(val_total, WINDOW_SIZE, N_CHANNELS))
    #Etichette
    train_y_parts, val_y_parts = [], []

    #Accumulatori 
    ch_sum = np.zeros(N_CHANNELS, dtype=np.float64)
    ch_sqsum = np.zeros(N_CHANNELS, dtype=np.float64)
    ch_count = np.zeros(N_CHANNELS, dtype=np.float64)

    train_off, val_off = 0, 0
    boundaries = {"train": [], "validation": []}

    #4 volte -> Bag, Hand, Hips, Torso
    for d in train_dirs:
        R = sizes[d.as_posix()]
        train_count = R - int(round(R * ES_FRAC))
        local = 0
        train_start_global, val_start_global = train_off, val_off
        for x_chunk, y_chunk in iter_window_chunks(d): # circa 24 volte per dirs
            n = x_chunk.shape[0]
            n_train = max(0, min(local + n, train_count) - local)
            if n_train > 0:
                x_train_part = x_chunk[:n_train]
                train_X[train_off:train_off + n_train] = x_train_part
                train_y_parts.append(y_chunk[:n_train])
                x_train_part64 = x_train_part.astype(np.float64)
                ch_sum += np.nansum(x_train_part64, axis=(0, 1))
                ch_sqsum += np.nansum(x_train_part64 ** 2, axis=(0, 1))
                ch_count += np.sum(~np.isnan(x_train_part), axis=(0, 1))
                train_off += n_train
            if n - n_train > 0:
                x_val_part = x_chunk[n_train:]
                val_X[val_off:val_off + (n - n_train)] = x_val_part
                val_y_parts.append(y_chunk[n_train:])
                val_off += (n - n_train)
            local += n
        boundaries["train"].append([train_start_global, train_off])
        boundaries["validation"].append([val_start_global, val_off])

    train_y = np.concatenate(train_y_parts)
    val_y = np.concatenate(val_y_parts)
    np.save(out_dir / f"{prefix}_train_y.npy", train_y)
    np.save(out_dir / f"{prefix}_validation_y.npy", val_y)

    mean = ch_sum / ch_count
    var = ch_sqsum / ch_count - mean ** 2
    std = np.sqrt(np.maximum(var, 1e-8))

    #Normalizzo i dati
    for arr in (train_X, val_X):
        for s in range(0, arr.shape[0], 16384):
            e = min(arr.shape[0], s + 16384)
            block = (arr[s:e] - mean) / std
            arr[s:e] = np.nan_to_num(block, nan=0.0)
        arr.flush()

    return mean, std, boundaries, train_y, val_y

# Prende i dati dalle 4 cartelle di validation -> 2 file npy
# 1 -> file npy (total, 500, 6) -> dati di test
# 2 -> file npy (total) per le label -> label di test
def build_test(test_dirs: list[Path], out_dir: Path, prefix: str, mean: np.ndarray, std: np.ndarray):
    sizes = {d.as_posix(): count_windows(d) for d in test_dirs}
    total = sum(sizes.values())
    print(f"test windows={total:,} from {[d.name for d in test_dirs]}")

    test_X = npformat.open_memmap(out_dir / f"{prefix}_test_X.npy", mode="w+",
                                  dtype=np.float32, shape=(total, WINDOW_SIZE, N_CHANNELS))
    y_parts = []
    off = 0
    boundaries = []
    for d in test_dirs:
        start = off
        for x_chunk, y_chunk in iter_window_chunks(d):
            n = x_chunk.shape[0]
            test_X[off:off + n] = np.nan_to_num((x_chunk - mean) / std, nan=0.0) # normalizzo subito
            y_parts.append(y_chunk)
            off += n
        boundaries.append([start, off, d.name])
    test_X.flush()
    test_y = np.concatenate(y_parts)
    np.save(out_dir / f"{prefix}_test_y.npy", test_y)
    print(f"  test label dist: {label_distribution(test_y)}")
    return boundaries, test_y


DATASET_ROOT = Path("DATASET")
OUT_DIR = Path("processed_6ch")
PREFIX = "shl_6ch_5class"

# Le 4 posizioni del corpo, ognuna in una cartella diversa lato train,
# tutte insieme sotto DATASET/validation lato test.
TRAIN_DIRS = [
    DATASET_ROOT / "train" / "Hips",
    DATASET_ROOT / "train-2" / "Bag",
    DATASET_ROOT / "train-3" / "Torso",
    DATASET_ROOT / "train-4" / "Hand",
]
TEST_DIRS = [
    DATASET_ROOT / "validation" / "Hips",
    DATASET_ROOT / "validation" / "Bag",
    DATASET_ROOT / "validation" / "Torso",
    DATASET_ROOT / "validation" / "Hand",
]


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    mean, std, train_bounds, train_y, val_y = build_train(TRAIN_DIRS, OUT_DIR, PREFIX)

    test_bounds, test_y = build_test(TEST_DIRS, OUT_DIR, PREFIX, mean, std)

    stats = {"mean": mean.tolist(), "std": std.tolist(), "channels": list(SIGNAL_NAMES)}
    (OUT_DIR / f"{PREFIX}_norm_stats.json").write_text(json.dumps(stats, indent=2))
    (OUT_DIR / f"{PREFIX}_label_map.json").write_text(json.dumps(CLASS_NAMES, indent=2))
    meta = {
        "channels": list(SIGNAL_NAMES),
        "n_channels": N_CHANNELS,
        "window_size": WINDOW_SIZE,
        "classes": CLASS_NAMES,
        "es_frac": ES_FRAC,
        "train_position_boundaries": train_bounds,
        "test_position_boundaries": test_bounds,
        "counts": {
            "train": int(train_y.size),
            "validation": int(val_y.size),
            "test": int(test_y.size),
        },
    }
    (OUT_DIR / f"{PREFIX}_meta.json").write_text(json.dumps(meta, indent=2))
    print("\nSaved everything to", OUT_DIR)
    print("Complete.")


if __name__ == "__main__":
    main()
