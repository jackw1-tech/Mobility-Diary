"""Normalizzazione delle finestre sensore nel formato atteso dal modello HAR.

Il mobile invia la matrice GREZZA `500x6` (unita fisiche). Qui la trasformiamo
nel formato "pronto" per il modello: z-score per canale con le statistiche SHL
(`norm_stats.json`) + imputazione dei NaN a 0 (media post-normalizzazione).

Questo e il preprocessing reale: resta valido quando il modello CNN+GRU verra
innestato al posto del classificatore placeholder.
"""

from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path

import numpy as np

_STATS_PATH = Path(__file__).resolve().parent / "norm_stats.json"


@lru_cache(maxsize=1)
def _stats() -> tuple[np.ndarray, np.ndarray]:
    data = json.loads(_STATS_PATH.read_text())
    mean = np.asarray(data["mean"], dtype=np.float32)
    std = np.asarray(data["std"], dtype=np.float32)
    std[std == 0] = 1.0
    return mean, std


def normalize_window(matrix: list[list[float]]) -> np.ndarray:
    """Da matrice grezza (righe x 6) a matrice normalizzata float32."""
    mean, std = _stats()
    arr = np.asarray(matrix, dtype=np.float32)
    arr = arr[:, :6]
    mean = mean[: arr.shape[1]]
    std = std[: arr.shape[1]]
    arr = (arr - mean) / std
    return np.nan_to_num(arr, nan=0.0, posinf=0.0, neginf=0.0)
