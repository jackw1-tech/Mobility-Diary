# Serve a unified backend diary projection with real and virtual stops

Status: ready-for-human

## Parent

- [PRD: HAR Idle Virtual Stops and Unified Diary Projection](../PRD.md)

## What to build

Build the backend read-model projection that becomes the single source of truth
for visible diary semantics.

This slice should merge persisted `MOVE`, persisted `STOP`, and persisted
`Virtual Stop Interval` into one projected timeline that still exposes only
user-facing `MOVE` and `STOP`. Real and virtual stops that overlap or touch
should be merged into one visible stop, and long HAR idle gaps should appear as
neutral `Sosta rilevata` stops unless another overlay enriches them.

The end-to-end result should be that the backend can explain missing stationary
time without inventing fake structural segments and without asking clients to
re-derive stop semantics.

Implementation detail that should be treated as part of the contract:

- `Real Stop` = persisted `MobilitySegment(kind=STOP)`
- `Virtual Stop` = persisted `Virtual Stop Interval`
- `Visible Stop` = projected stop returned by the backend after temporal merge

Recommended projection algorithm:

1. Collect all visible `MOVE` segments as-is.
2. Collect all stop-like intervals from two sources: `Real Stop` and
   `Virtual Stop`.
3. Sort stop-like intervals by `(start, end)`.
4. Scan left-to-right and merge any two stop-like intervals that overlap,
   touch, or are within the configured stop-gap tolerance.
5. Emit one `Visible Stop` for each merged stop block, with:
   `start = min(starts)` and `end = max(ends)`.
6. Insert the resulting `Visible Stop` entries back into the projected
   timeline between visible moves, ordered by time.

Important semantic rule:
`MOVE` entries are never merged with stop-like intervals. A virtual stop may
fill an empty temporal gap between moves, but it must not widen, shrink or
relabel a persisted move entry itself.

## Acceptance criteria

- [ ] The backend exposes one projected diary timeline that merges real `STOP` intervals and virtual-stop evidence into visible `STOP` entries.
- [ ] The projected timeline exposes no final visible `MOVE/IDLE` outcome.
- [ ] Overlapping or adjacent real and virtual stops are merged into one visible stop with correct duration boundaries.
- [ ] The projection contract explicitly covers at least these patterns: real-stop contains virtual-stop, virtual-stop contains real-stop, isolated virtual-stop between two moves, and virtual-stop bridging nearby real stops.
- [ ] Stop labels are assigned after temporal merging, so one merged visible stop yields one final label decision.
- [ ] Significant-place overlays can still enrich a visible stop without rewriting persisted structure.
- [ ] Backend tests cover mixed real/virtual stop merging and neutral labeling for HAR-derived visible stops.

## Blocked by

- [Materialize HAR idle runs and virtual stop intervals](02-materialize-har-idle-runs-and-virtual-stop-intervals.md)

## Comments

- `mobility/diary_projection.py` is now the single backend seam for visible diary semantics. It merges:
  - persisted real `STOP` segments;
  - legacy `MOVE/IDLE` rows kept as backward-compatible stop-like evidence;
  - persisted `VirtualStopInterval` rows from HAR post-processing.
- The projection emits only visible `MOVE` and visible `STOP`, never a final visible `MOVE/IDLE`.
- Real and virtual stops are merged interval-wise when they overlap or touch. The merge tolerance is explicit (`STOP_GAP_TOLERANCE = 0`) so the behavior is deterministic and easy to widen later if product wants it.
- `get_trip_diary` now consumes `project_trip_diary_segments(trip)`, so significant-place overlay happens after stop merging on the final visible stop block.
- The web dashboard backend builder (`accounts/web_users_api.py`) was switched to the same seam, so backend diary payloads stay aligned across mobile and web readers.
- Simplification pass applied after implementation:
  - extracted `project_trip_diary_segments(trip)` so API consumers no longer know which persisted tables compose the visible diary;
  - kept projection pure and isolated instead of duplicating merge logic in endpoints.
- Added focused tests for the projection contract:
  - real-stop contains virtual-stop;
  - virtual-stop contains real-stop;
  - isolated virtual-stop between two moves;
  - virtual-stop bridging two real stops.
- Added API tests proving:
  - a virtual stop appears as a visible stop even without a persisted `STOP`;
  - significant-place overlay still enriches a stop projected from `VirtualStopInterval`.
- Verification:
  - `python3 -m py_compile mobility/diary_projection.py mobility/api.py ../ninja/accounts/web_users_api.py`
  - `../.venv/bin/pytest mobility/tests/test_diary_projection.py -q`
  - `../.venv/bin/pytest mobility/tests/test_trip_track.py -q`
  - `../.venv/bin/pytest --reuse-db accounts/tests/test_web_users_api.py -q -k "trip_dashboard"`
