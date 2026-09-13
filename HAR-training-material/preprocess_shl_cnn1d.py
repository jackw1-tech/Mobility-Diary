#!/usr/bin/env python3
"""
Memory-conscious SHL/HAR preprocessing for a 1D CNN.

Reads each sensor position one at a time, samples/keeps rows from each chunk,
stacks Acc/Gyr channels into X with shape (N, 500, 6), remaps labels, and
optionally saves X/y as .npy files.
"""

from __future__ import annotations

import argparse
import gc
import json
import os
import resource
import sys
from pathlib import Path
from typing import Iterable

import numpy as np
import pandas as pd


SIGNAL_NAMES = ("Acc_x", "Acc_y", "Acc_z", "Gyr_x", "Gyr_y", "Gyr_z")
LABEL_NAME = "Label"
WINDOW_SIZE = 500
DEFAULT_SAMPLE_FRAC = 1.00
DEFAULT_CHUNK_SIZE = 16_384
DEFAULT_MEMORY_BUDGET_GB = 24.0
DEFAULT_SPLIT_RATIOS = (0.70, 0.15, 0.15)
CLASS_NAMES = {
    0: "IDLE",
    1: "WALKING",
    2: "RUNNING",
    3: "BIKING",
    4: "DRIVING",
    5: "PUBLIC_TRANSPORT",
}


def rss_message() -> str:
    """Return a best-effort memory usage string without requiring psutil."""
    try:
        import psutil  # type: ignore

        rss_gb = psutil.Process(os.getpid()).memory_info().rss / (1024**3)
        return f"RSS: {rss_gb:.2f} GB"
    except Exception:
        peak = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
        # macOS reports bytes; Linux reports KiB.
        peak_bytes = peak if sys.platform == "darwin" else peak * 1024
        return f"Peak RSS: {peak_bytes / (1024**3):.2f} GB"


def bytes_to_gib(n_bytes: float) -> float:
    """Convert bytes to GiB."""
    return n_bytes / (1024**3)


def tensor_gib(n_rows: int, dtype: np.dtype = np.dtype(np.float32)) -> float:
    """Return the size of X=(n_rows, 500, 6) in GiB."""
    n_bytes = n_rows * WINDOW_SIZE * len(SIGNAL_NAMES) * dtype.itemsize
    return bytes_to_gib(n_bytes)


def print_memory_plan(sample_frac: float, chunk_size: int, memory_budget_gb: float) -> None:
    """Print a rough RAM plan for the chosen preprocessing settings."""
    raw_signal_chunk_gb = tensor_gib(chunk_size)
    sampled_chunk_gb = tensor_gib(int(round(chunk_size * sample_frac)))

    print("Memory plan:")
    print(f"  sample_frac={sample_frac:.2f}")
    print(f"  chunk_size={chunk_size:,} windows")
    print(f"  raw signal chunk approx={raw_signal_chunk_gb:.2f} GiB")
    print(f"  sampled X chunk approx={sampled_chunk_gb:.2f} GiB")
    print(f"  RAM budget target={memory_budget_gb:.1f} GiB")


def discover_position_dirs(dataset_root: Path) -> list[Path]:
    """Find leaf directories containing all required signal and label files."""
    required_files = [f"{name}.txt" for name in (*SIGNAL_NAMES, LABEL_NAME)]
    position_dirs = []

    for path in sorted(dataset_root.rglob("*")):
        if path.is_dir() and all((path / filename).is_file() for filename in required_files):
            position_dirs.append(path)

    if not position_dirs:
        expected = ", ".join(required_files)
        raise FileNotFoundError(
            f"No valid position folders found under {dataset_root}. "
            f"Expected folders containing: {expected}"
        )

    return position_dirs


def read_signal_chunks(position_dir: Path, chunk_size: int) -> dict[str, Iterable[pd.DataFrame]]:
    """Create one chunk iterator per signal file."""
    return {
        name: pd.read_csv(
            position_dir / f"{name}.txt",
            sep=r"\s+",
            header=None,
            dtype=np.float32,
            chunksize=chunk_size,
        )
        for name in SIGNAL_NAMES
    }


def read_label_chunks(position_dir: Path, chunk_size: int) -> Iterable[pd.DataFrame]:
    """Read only the first label column, even if Label.txt has 500 columns."""
    return pd.read_csv(
        position_dir / f"{LABEL_NAME}.txt",
        sep=r"\s+",
        header=None,
        usecols=[0],
        dtype=np.int16,
        chunksize=chunk_size,
    )


def sample_indices(n_rows: int, sample_frac: float, rng: np.random.Generator) -> np.ndarray:
    """Select an exact per-chunk random sample of row indices."""
    if sample_frac >= 1.0:
        return np.arange(n_rows)

    n_keep = int(round(n_rows * sample_frac))
    if n_keep <= 0:
        return np.array([], dtype=np.int64)

    return np.sort(rng.choice(n_rows, size=n_keep, replace=False))


def remap_labels(raw_labels: np.ndarray) -> np.ndarray:
    """
    Map SHL labels:
      1 -> 0 IDLE
      2 -> 1 WALKING
      3 -> 2 RUNNING
      4 -> 3 BIKING
      5 -> 4 DRIVING
      6,7,8 -> 5 PUBLIC_TRANSPORT
    Unknown labels become -1 and are filtered out later.
    """
    y = np.full(raw_labels.shape, -1, dtype=np.int64)
    y[raw_labels == 1] = 0
    y[raw_labels == 2] = 1
    y[raw_labels == 3] = 2
    y[raw_labels == 4] = 3
    y[raw_labels == 5] = 4
    y[np.isin(raw_labels, (6, 7, 8))] = 5
    return y


def label_distribution(y: np.ndarray) -> dict[str, int]:
    """Return counts keyed by both numeric id and readable class name."""
    labels, counts = np.unique(y, return_counts=True)
    return {
        f"{int(label)}:{CLASS_NAMES.get(int(label), 'UNKNOWN')}": int(count)
        for label, count in zip(labels, counts)
    }


def process_position(
    position_dir: Path,
    sample_frac: float,
    chunk_size: int,
    rng: np.random.Generator,
    progress_every: int,
    max_chunks: int | None,
) -> tuple[list[np.ndarray], list[np.ndarray], int, int]:
    """Process one sensor position and return sampled X/y chunks."""
    signal_readers = read_signal_chunks(position_dir, chunk_size)
    label_reader = iter(read_label_chunks(position_dir, chunk_size))

    x_parts: list[np.ndarray] = []
    y_parts: list[np.ndarray] = []
    total_seen = 0
    total_kept = 0
    chunk_number = 0

    print(f"\n--- Position: {position_dir} ---")

    while True:
        if max_chunks is not None and chunk_number >= max_chunks:
            print(f"Reached max chunks for smoke test: {max_chunks}")
            break

        try:
            label_chunk = next(label_reader)
            signal_chunks = {name: next(iterable) for name, iterable in signal_readers.items()}
        except StopIteration:
            break

        chunk_number += 1
        n_rows = len(label_chunk)
        total_seen += n_rows

        for name, data in signal_chunks.items():
            if len(data) != n_rows:
                raise ValueError(f"Row mismatch in {position_dir}: {name} has {len(data)}, labels have {n_rows}")
            if data.shape[1] != WINDOW_SIZE:
                raise ValueError(
                    f"Unexpected window size in {position_dir / f'{name}.txt'}: "
                    f"got {data.shape[1]}, expected {WINDOW_SIZE}"
                )

        keep_idx = sample_indices(n_rows, sample_frac, rng)
        if keep_idx.size:
            channels = [
                signal_chunks[name].iloc[keep_idx].to_numpy(dtype=np.float32, copy=False)
                for name in SIGNAL_NAMES
            ]
            x_chunk = np.stack(channels, axis=-1)

            raw_labels = label_chunk.iloc[keep_idx, 0].to_numpy(dtype=np.int16, copy=False)
            y_chunk = remap_labels(raw_labels)

            valid = y_chunk >= 0
            if not np.all(valid):
                dropped = int(np.size(valid) - np.count_nonzero(valid))
                print(f"Warning: dropped {dropped} rows with unknown labels in {position_dir.name}")
                x_chunk = x_chunk[valid]
                y_chunk = y_chunk[valid]

            if y_chunk.size:
                x_parts.append(x_chunk)
                y_parts.append(y_chunk)
                total_kept += int(y_chunk.size)

        if progress_every > 0 and chunk_number % progress_every == 0:
            print(
                f"chunk={chunk_number:04d} seen={total_seen:,} kept={total_kept:,} "
                f"{rss_message()}"
            )

        del label_chunk, signal_chunks
        gc.collect()

    print(
        f"Done {position_dir.name}: seen={total_seen:,}, kept={total_kept:,}, "
        f"kept_pct={100 * total_kept / max(total_seen, 1):.2f}%, {rss_message()}"
    )
    return x_parts, y_parts, total_seen, total_kept


def build_dataset(
    dataset_root: Path,
    sample_frac: float = DEFAULT_SAMPLE_FRAC,
    chunk_size: int = DEFAULT_CHUNK_SIZE,
    seed: int = 42,
    progress_every: int = 10,
    max_chunks_per_position: int | None = None,
    memory_budget_gb: float = DEFAULT_MEMORY_BUDGET_GB,
) -> tuple[np.ndarray, np.ndarray]:
    """Build shuffled X/y arrays from all discovered sensor positions."""
    if not 0.0 < sample_frac <= 1.0:
        raise ValueError("--sample-frac must be in the interval (0, 1].")
    if chunk_size <= 0:
        raise ValueError("--chunk-size must be positive.")

    rng = np.random.default_rng(seed)
    position_dirs = discover_position_dirs(dataset_root)
    print_memory_plan(sample_frac, chunk_size, memory_budget_gb)

    print("Discovered position folders:")
    for position_dir in position_dirs:
        print(f"  - {position_dir}")

    all_x_parts: list[np.ndarray] = []
    all_y_parts: list[np.ndarray] = []
    total_seen = 0
    total_kept = 0

    for position_dir in position_dirs:
        x_parts, y_parts, seen, kept = process_position(
            position_dir=position_dir,
            sample_frac=sample_frac,
            chunk_size=chunk_size,
            rng=rng,
            progress_every=progress_every,
            max_chunks=max_chunks_per_position,
        )
        all_x_parts.extend(x_parts)
        all_y_parts.extend(y_parts)
        total_seen += seen
        total_kept += kept

        del x_parts, y_parts
        gc.collect()
        print(f"Accumulated sampled rows: {total_kept:,} / {total_seen:,}. {rss_message()}")

    if not all_x_parts:
        raise RuntimeError("No rows were sampled. Increase --sample-frac or check the input files.")

    final_x_gb = tensor_gib(total_kept)
    estimated_peak_gb = 2.5 * final_x_gb + tensor_gib(chunk_size)
    print("\nFinal tensor estimate:")
    print(f"  sampled windows={total_kept:,}")
    print(f"  X approx size={final_x_gb:.2f} GiB")
    print(f"  estimated peak during concat/shuffle={estimated_peak_gb:.2f} GiB")
    if estimated_peak_gb > memory_budget_gb:
        print(
            "  Warning: estimated peak exceeds the RAM budget. "
            "Consider lowering --sample-frac or --chunk-size."
        )

    print("\nConcatenating sampled chunks...")
    X = np.concatenate(all_x_parts, axis=0).astype(np.float32, copy=False)
    y = np.concatenate(all_y_parts, axis=0).astype(np.int64, copy=False)

    del all_x_parts, all_y_parts
    gc.collect()

    print(f"Sampled dataset: X={X.shape}, y={y.shape}, {rss_message()}")
    print(f"Label distribution after remap: {label_distribution(y)}")
    return X, y


def stratified_split_indices(
    y: np.ndarray,
    train_frac: float,
    val_frac: float,
    test_frac: float,
    rng: np.random.Generator,
) -> dict[str, np.ndarray]:
    """Create shuffled train/val/test indices while preserving label balance."""
    total = train_frac + val_frac + test_frac
    if not np.isclose(total, 1.0):
        raise ValueError(f"Split ratios must sum to 1.0, got {total:.4f}.")
    if min(train_frac, val_frac, test_frac) <= 0:
        raise ValueError("Split ratios must all be positive.")

    split_parts: dict[str, list[np.ndarray]] = {"train": [], "val": [], "test": []}

    for label in np.unique(y):
        label_indices = np.flatnonzero(y == label)
        rng.shuffle(label_indices)

        n_label = label_indices.size
        n_train = int(round(n_label * train_frac))
        n_val = int(round(n_label * val_frac))
        if n_train + n_val > n_label:
            n_val = max(0, n_label - n_train)

        split_parts["train"].append(label_indices[:n_train])
        split_parts["val"].append(label_indices[n_train : n_train + n_val])
        split_parts["test"].append(label_indices[n_train + n_val :])

    splits = {
        name: np.concatenate(parts).astype(np.int64, copy=False)
        for name, parts in split_parts.items()
    }
    for indices in splits.values():
        rng.shuffle(indices)

    return splits


def save_full_arrays(X: np.ndarray, y: np.ndarray, out_dir: Path, prefix: str) -> None:
    """Optionally save the full sampled arrays before splitting."""
    x_path = out_dir / f"{prefix}_full_X.npy"
    y_path = out_dir / f"{prefix}_full_y.npy"

    print(f"\nSaving full sampled X to {x_path}")
    np.save(x_path, X)
    print(f"Saving full sampled y to {y_path}")
    np.save(y_path, y)


def save_split_arrays(
    X: np.ndarray,
    y: np.ndarray,
    out_dir: Path,
    prefix: str,
    sample_frac: float,
    split_ratios: tuple[float, float, float],
    seed: int,
    save_full: bool,
) -> None:
    """Save stratified train/val/test .npy arrays plus metadata."""
    out_dir.mkdir(parents=True, exist_ok=True)
    label_map_path = out_dir / f"{prefix}_label_map.json"
    split_meta_path = out_dir / f"{prefix}_split_meta.json"

    if save_full:
        save_full_arrays(X, y, out_dir, prefix)

    print("\nCreating stratified train/val/test split...")
    split_rng = np.random.default_rng(seed)
    splits = stratified_split_indices(y, *split_ratios, rng=split_rng)

    metadata = {
        "sample_fraction": sample_frac,
        "split_ratios": {
            "train": split_ratios[0],
            "val": split_ratios[1],
            "test": split_ratios[2],
        },
        "class_names": CLASS_NAMES,
        "splits": {},
    }

    for split_name, indices in splits.items():
        x_path = out_dir / f"{prefix}_{split_name}_X.npy"
        y_path = out_dir / f"{prefix}_{split_name}_y.npy"
        split_y = y[indices]

        print(
            f"Saving {split_name}: X={(indices.size, WINDOW_SIZE, len(SIGNAL_NAMES))}, "
            f"y={(indices.size,)}, distribution={label_distribution(split_y)}"
        )
        np.save(x_path, X[indices])
        np.save(y_path, split_y)
        metadata["splits"][split_name] = {
            "rows": int(indices.size),
            "x_file": x_path.name,
            "y_file": y_path.name,
            "label_distribution": label_distribution(split_y),
        }

        del split_y
        gc.collect()

    print(f"Saving label map to {label_map_path}")
    label_map_path.write_text(json.dumps(CLASS_NAMES, indent=2), encoding="utf-8")
    print(f"Saving split metadata to {split_meta_path}")
    split_meta_path.write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    print(f"Saved. {rss_message()}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create a sampled SHL/HAR tensor X=(N, 500, 6) and remapped labels y."
    )
    parser.add_argument("--dataset-root", type=Path, default=Path("DATASET"))
    parser.add_argument("--out-dir", type=Path, default=Path("processed"))
    parser.add_argument("--output-prefix", default="shl_cnn1d_full_100pct_6class")
    parser.add_argument("--sample-frac", type=float, default=DEFAULT_SAMPLE_FRAC)
    parser.add_argument(
        "--split-ratios",
        type=float,
        nargs=3,
        default=DEFAULT_SPLIT_RATIOS,
        metavar=("TRAIN", "VAL", "TEST"),
        help="Train/validation/test ratios. Default: 0.70 0.15 0.15.",
    )
    parser.add_argument("--chunk-size", type=int, default=DEFAULT_CHUNK_SIZE)
    parser.add_argument(
        "--memory-budget-gb",
        type=float,
        default=DEFAULT_MEMORY_BUDGET_GB,
        help="Soft RAM budget used for warnings and progress messages.",
    )
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--progress-every", type=int, default=10)
    parser.add_argument("--save-full", action="store_true", help="Also save the full sampled X/y before splitting.")
    parser.add_argument("--no-save", action="store_true", help="Build X/y but do not write .npy files.")
    parser.add_argument(
        "--max-chunks-per-position",
        type=int,
        default=None,
        help="Optional smoke-test limit. Leave unset for the full dataset.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()

    X, y = build_dataset(
        dataset_root=args.dataset_root,
        sample_frac=args.sample_frac,
        chunk_size=args.chunk_size,
        seed=args.seed,
        progress_every=args.progress_every,
        max_chunks_per_position=args.max_chunks_per_position,
        memory_budget_gb=args.memory_budget_gb,
    )

    if not args.no_save:
        save_split_arrays(
            X=X,
            y=y,
            out_dir=args.out_dir,
            prefix=args.output_prefix,
            sample_frac=args.sample_frac,
            split_ratios=tuple(args.split_ratios),
            seed=args.seed,
            save_full=args.save_full,
        )

    print("\nComplete.")


if __name__ == "__main__":
    main()
