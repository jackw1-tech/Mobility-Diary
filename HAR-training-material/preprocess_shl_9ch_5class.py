#!/usr/bin/env python3
"""
9-channel, 5-class SHL preprocessing with proper protocol + normalization.

Differences from the earlier scripts:
  - 9 channels: Acc + Gyr + Mag (magnetometer added to break the IDLE vs
    stopped-vehicle ambiguity).
  - 5 classes: DRIVING + PUBLIC_TRANSPORT merged into MOVING_VEHICLE.
  - Correct protocol, no leakage:
        train folders            -> training data
        last ES_FRAC of train    -> early-stopping set (temporal block)
        official validation      -> untouched, final honest evaluation
  - Per-channel standardization (mean/std) fitted ONLY on the train-fit data
    and applied to every split. Stats are saved for inference.
  - Chronological order preserved (no shuffle) so a temporal model / smoothing
    can reuse the arrays. Per-position boundaries are saved in the metadata.

Memory-safe: arrays are written straight to disk via np.lib.format.open_memmap,
so only one chunk lives in RAM at a time.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import numpy.lib.format as npformat
import pandas as pd


SIGNAL_NAMES = (
    "Acc_x", "Acc_y", "Acc_z",
    "Gyr_x", "Gyr_y", "Gyr_z",
    "Mag_x", "Mag_y", "Mag_z",
)
N_CHANNELS = len(SIGNAL_NAMES)
LABEL_NAME = "Label"
WINDOW_SIZE = 500
CHUNK_SIZE = 8_192
ES_FRAC = 0.15  # last fraction of each train position used for early stopping
CLASS_NAMES = {
    0: "IDLE",
    1: "WALKING",
    2: "RUNNING",
    3: "BIKING",
    4: "MOVING_VEHICLE",
}


def remap_labels(raw: np.ndarray) -> np.ndarray:
    """1->0, 2->1, 3->2, 4->3, 5/6/7/8->4. Raises on unknown labels."""
    y = np.full(raw.shape, -1, dtype=np.int64)
    y[raw == 1] = 0
    y[raw == 2] = 1
    y[raw == 3] = 2
    y[raw == 4] = 3
    y[np.isin(raw, (5, 6, 7, 8))] = 4
    if np.any(y < 0):
        raise ValueError("Unknown label encountered; fixed-size layout assumes labels 1-8 only.")
    return y


def label_distribution(y: np.ndarray) -> dict[str, int]:
    labels, counts = np.unique(y, return_counts=True)
    return {f"{int(l)}:{CLASS_NAMES.get(int(l), '?')}": int(c) for l, c in zip(labels, counts)}


def position_dirs_under(root: Path, exclude: tuple[str, ...] = ()) -> list[Path]:
    """Leaf dirs holding all 9 signals + Label, excluding given path substrings."""
    required = [f"{n}.txt" for n in (*SIGNAL_NAMES, LABEL_NAME)]
    found = []
    for path in sorted(root.rglob("*")):
        if not path.is_dir():
            continue
        if any(token in path.as_posix() for token in exclude):
            continue
        if all((path / f).is_file() for f in required):
            found.append(path)
    if not found:
        raise FileNotFoundError(f"No valid position folders under {root} (excluding {exclude}).")
    return found


def count_windows(position_dir: Path) -> int:
    with open(position_dir / f"{LABEL_NAME}.txt", "rb") as fh:
        return sum(1 for _ in fh)


def iter_window_chunks(position_dir: Path):
    """Yield (x_chunk (n,500,9) float32, y_chunk (n,) int64) per chunk, in order."""
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
            channels.append(data.to_numpy(dtype=np.float32, copy=False))
        x_chunk = np.stack(channels, axis=-1)
        y_chunk = remap_labels(label_chunk.iloc[:, 0].to_numpy(dtype=np.int16, copy=False))
        yield x_chunk, y_chunk


def build_train(train_dirs: list[Path], out_dir: Path, prefix: str):
    """Fill train-fit / train-es memmaps, return stats + sizes + boundaries."""
    sizes = {d.as_posix(): count_windows(d) for d in train_dirs}
    fit_total = sum(r - int(round(r * ES_FRAC)) for r in sizes.values())
    es_total = sum(int(round(r * ES_FRAC)) for r in sizes.values())
    print(f"train-fit windows={fit_total:,}  train-es windows={es_total:,}")

    fit_X = npformat.open_memmap(out_dir / f"{prefix}_trainfit_X.npy", mode="w+",
                                 dtype=np.float32, shape=(fit_total, WINDOW_SIZE, N_CHANNELS))
    es_X = npformat.open_memmap(out_dir / f"{prefix}_traines_X.npy", mode="w+",
                                dtype=np.float32, shape=(es_total, WINDOW_SIZE, N_CHANNELS))
    fit_y_parts, es_y_parts = [], []

    # Running NaN-aware stats over fit data only (float64, per channel).
    # SHL Gyr/Mag streams contain missing values (NaN); they are imputed to the
    # channel mean (i.e. 0 after standardization) and excluded from the stats.
    ch_sum = np.zeros(N_CHANNELS, dtype=np.float64)
    ch_sqsum = np.zeros(N_CHANNELS, dtype=np.float64)
    ch_count = np.zeros(N_CHANNELS, dtype=np.float64)

    fit_off, es_off = 0, 0
    boundaries = {"trainfit": [], "traines": []}

    for d in train_dirs:
        R = sizes[d.as_posix()]
        fit_count = R - int(round(R * ES_FRAC))
        local = 0
        fit_start_global, es_start_global = fit_off, es_off
        print(f"  {d.as_posix()}: {R:,} windows (fit {fit_count:,}, es {R-fit_count:,})")
        for x_chunk, y_chunk in iter_window_chunks(d):
            n = x_chunk.shape[0]
            # split this chunk at the fit/es boundary (single split point)
            n_fit = max(0, min(local + n, fit_count) - local)
            if n_fit > 0:
                xf = x_chunk[:n_fit]
                fit_X[fit_off:fit_off + n_fit] = xf
                fit_y_parts.append(y_chunk[:n_fit])
                xf64 = xf.astype(np.float64)
                ch_sum += np.nansum(xf64, axis=(0, 1))
                ch_sqsum += np.nansum(xf64 ** 2, axis=(0, 1))
                ch_count += np.sum(~np.isnan(xf), axis=(0, 1))
                fit_off += n_fit
            if n - n_fit > 0:
                xe = x_chunk[n_fit:]
                es_X[es_off:es_off + (n - n_fit)] = xe
                es_y_parts.append(y_chunk[n_fit:])
                es_off += (n - n_fit)
            local += n
        boundaries["trainfit"].append([fit_start_global, fit_off])
        boundaries["traines"].append([es_start_global, es_off])

    fit_y = np.concatenate(fit_y_parts)
    es_y = np.concatenate(es_y_parts)
    np.save(out_dir / f"{prefix}_trainfit_y.npy", fit_y)
    np.save(out_dir / f"{prefix}_traines_y.npy", es_y)

    total_cells = fit_total * WINDOW_SIZE
    nan_frac = 1.0 - ch_count / total_cells
    mean = ch_sum / ch_count
    var = ch_sqsum / ch_count - mean ** 2
    std = np.sqrt(np.maximum(var, 1e-8))
    print(f"  per-channel mean    ={np.round(mean,3)}")
    print(f"  per-channel std     ={np.round(std,3)}")
    print(f"  per-channel NaN frac={np.round(nan_frac,4)}")

    # In-place standardization of both memmaps, row-chunked to keep RAM low.
    # NaNs become 0 (the channel mean) via nan_to_num.
    for arr in (fit_X, es_X):
        for s in range(0, arr.shape[0], 16384):
            e = min(arr.shape[0], s + 16384)
            block = (arr[s:e] - mean) / std
            arr[s:e] = np.nan_to_num(block, nan=0.0)
        arr.flush()

    print(f"  fit label dist: {label_distribution(fit_y)}")
    print(f"  es  label dist: {label_distribution(es_y)}")
    return mean, std, nan_frac, boundaries, fit_y, es_y


def build_validation(val_root: Path, out_dir: Path, prefix: str, mean: np.ndarray, std: np.ndarray):
    val_dirs = position_dirs_under(val_root)
    sizes = {d.as_posix(): count_windows(d) for d in val_dirs}
    total = sum(sizes.values())
    print(f"validation windows={total:,} from {[d.name for d in val_dirs]}")

    val_X = npformat.open_memmap(out_dir / f"{prefix}_val_X.npy", mode="w+",
                                 dtype=np.float32, shape=(total, WINDOW_SIZE, N_CHANNELS))
    y_parts = []
    off = 0
    boundaries = []
    for d in val_dirs:
        start = off
        for x_chunk, y_chunk in iter_window_chunks(d):
            n = x_chunk.shape[0]
            val_X[off:off + n] = np.nan_to_num((x_chunk - mean) / std, nan=0.0)
            y_parts.append(y_chunk)
            off += n
        boundaries.append([start, off, d.name])
    val_X.flush()
    val_y = np.concatenate(y_parts)
    np.save(out_dir / f"{prefix}_val_y.npy", val_y)
    print(f"  val label dist: {label_distribution(val_y)}")
    return boundaries, val_y


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="9-channel 5-class SHL preprocessing (proper protocol + normalization).")
    p.add_argument("--dataset-root", type=Path, default=Path("DATASET"))
    p.add_argument("--val-root", type=Path, default=Path("DATASET/validation"))
    p.add_argument("--out-dir", type=Path, default=Path("processed_9ch"))
    p.add_argument("--prefix", default="shl_9ch_5class")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    args.out_dir.mkdir(parents=True, exist_ok=True)

    train_dirs = position_dirs_under(args.dataset_root, exclude=("validation", "test"))
    print("Train positions:", [d.as_posix() for d in train_dirs])

    print("\n=== Building train (fit + early-stopping) ===")
    mean, std, nan_frac, train_bounds, fit_y, es_y = build_train(train_dirs, args.out_dir, args.prefix)

    print("\n=== Building validation ===")
    val_bounds, val_y = build_validation(args.val_root, args.out_dir, args.prefix, mean, std)

    stats = {"mean": mean.tolist(), "std": std.tolist(), "nan_frac": nan_frac.tolist(),
             "channels": list(SIGNAL_NAMES)}
    (args.out_dir / f"{args.prefix}_norm_stats.json").write_text(json.dumps(stats, indent=2))
    (args.out_dir / f"{args.prefix}_label_map.json").write_text(json.dumps(CLASS_NAMES, indent=2))
    meta = {
        "channels": list(SIGNAL_NAMES),
        "n_channels": N_CHANNELS,
        "window_size": WINDOW_SIZE,
        "classes": CLASS_NAMES,
        "es_frac": ES_FRAC,
        "train_position_boundaries": train_bounds,
        "val_position_boundaries": val_bounds,
        "counts": {
            "trainfit": int(fit_y.size),
            "traines": int(es_y.size),
            "val": int(val_y.size),
        },
    }
    (args.out_dir / f"{args.prefix}_meta.json").write_text(json.dumps(meta, indent=2))
    print("\nSaved everything to", args.out_dir)
    print("Complete.")


if __name__ == "__main__":
    main()
