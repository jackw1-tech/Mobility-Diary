# Align diary and export APIs to the backend stop projection

Status: ready-for-agent

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
