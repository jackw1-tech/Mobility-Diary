from __future__ import annotations

import inspect
import time
from typing import Any

from ..ml.pipeline import PipelineSensorWindow, run_pipeline
from ..models import Trip


def run_har_pipeline_with_timings(
    trip: Trip,
    *,
    sensor_windows: list[PipelineSensorWindow],
    timings: dict[str, Any],
) -> dict:
    try:
        parameters = inspect.signature(run_pipeline).parameters
    except (TypeError, ValueError):
        parameters = {}
    if "timings" in parameters:
        return run_pipeline(
            trip,
            sensor_windows=sensor_windows,
            timings=timings,
        )

    pipeline_start = time.perf_counter()
    result = run_pipeline(trip, sensor_windows=sensor_windows)
    _add_elapsed_ms(timings, "pipeline_total_ms", pipeline_start)
    return result


def _add_elapsed_ms(timings: dict[str, Any] | None, key: str, start: float) -> None:
    if timings is None:
        return
    elapsed = (time.perf_counter() - start) * 1000
    timings[key] = round(float(timings.get(key, 0.0)) + elapsed, 2)
