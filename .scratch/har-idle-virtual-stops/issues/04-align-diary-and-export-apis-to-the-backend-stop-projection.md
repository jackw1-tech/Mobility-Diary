# Align diary and export APIs to the backend stop projection

Status: ready-for-human

## Parent

- [PRD: HAR Idle Virtual Stops and Unified Diary Projection](../PRD.md)

## What to build

Move the trip diary and export surfaces onto the unified backend projection so
every consumer sees the same stop semantics.

This slice should make the backend diary API, privacy-aware diary output, and
mobile/web export-ready representations read from the projected timeline rather
than from raw segment lists or client-side stop heuristics.

The end-to-end result should be that a trip exported or fetched through backend
APIs already contains the resolved distinction between movement and visible
stops, including HAR-derived virtual stops.

Implementation detail that should be treated as part of the contract:

- APIs should expose the already-merged `Visible Stop` timeline rather than raw
  `Real Stop` plus `Virtual Stop` ingredients.
- Client consumers should not need to know whether one visible stop came from a
  real stop, a virtual stop, or a merged combination of both unless a specific
  diagnostic/debug surface is later introduced.

## Acceptance criteria

- [ ] The main trip diary API returns projected stop semantics rather than requiring clients to merge stop-like intervals locally.
- [ ] Privacy-aware and export-ready diary representations use the same projected stop semantics.
- [ ] Stop counts, stopped time, and movement time in backend-facing payloads are consistent with the projected timeline.
- [ ] Backend-facing payloads do not require mobile or web to reconstruct one visible stop from multiple stop-like backend rows.
- [ ] Existing significant-place and privacy overlays continue to work on top of the projected stop semantics.
- [ ] Backend tests cover parity between diary API output and export/privacy-aware output for trips containing virtual stops.

## Blocked by

- [Serve a unified backend diary projection with real and virtual stops](03-serve-a-unified-backend-diary-projection-with-real-and-virtual-stops.md)

## Comments

- The mobile diary API was already reading from the projected visible timeline after issue 03; this slice moved the privacy/export surface onto the same semantics.
- `get_trip_privacy_export` now builds export segments from the projected timeline instead of iterating raw `trip.segments`.
- Stop titles are now decided after stop merging:
  - non-precise export keeps the generic privacy wording;
  - precise export keeps one place label only when the merged visible stop maps to exactly one distinct persisted real-stop label;
  - otherwise the precise export falls back to neutral `Sosta rilevata`, which also covers pure virtual stops.
- This means the export payload no longer leaks the internal distinction between `Real Stop` and `Virtual Stop`: clients receive one already-resolved visible stop list.
- Existing privacy behavior still works because masking happens after projection, not before.
- Existing stop label behavior still works for precise export on real labeled stops, even when a touching/overlapping virtual stop extends the visible stop block.
- Simplification pass applied after implementation:
  - kept the merge logic centralized in `project_diary_segments`;
  - added only a thin export-only helper to resolve the final stop title from overlapping persisted real stops, instead of duplicating projection logic.
- Added backend tests for:
  - parity between `/trips/{id}/diary` and `/trips/{id}/privacy-export` on a trip containing a virtual stop;
  - preserving one labeled visible stop after real-stop + virtual-stop merge.
- Verification:
  - `python3 -m py_compile mobility/api.py mobility/tests/test_privacy_export.py`
  - `../.venv/bin/pytest --reuse-db mobility/tests/test_privacy_export.py -q`
  - `../.venv/bin/pytest --reuse-db mobility/tests/test_trip_track.py -q`
  - `../.venv/bin/pytest --reuse-db accounts/tests/test_web_users_api.py -q -k "trip_dashboard"`
