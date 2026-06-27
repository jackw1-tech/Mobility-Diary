# Consume the backend stop projection in mobile trip detail

Status: ready-for-agent

## Parent

- [PRD: HAR Idle Virtual Stops and Unified Diary Projection](../PRD.md)

## What to build

Update mobile trip detail to consume backend-projected stop semantics instead of
maintaining its own definition of stop-like segments.

This slice should make the mobile map, diary tab and statistics tab trust the
backend-projected timeline for visible stops, counts and durations. Mobile may
still format labels and cards, but it should no longer own the semantic merge
between real stops, `HAR IDLE`, and virtual stops.

The end-to-end result should be that mobile trip detail shows the same visible
stops and stopped-time totals returned by the backend, with less presenter
logic and fewer local edge cases.

## Acceptance criteria

- [ ] Mobile trip detail reads backend-projected stop semantics for diary rows, map stop markers and statistics.
- [ ] Mobile no longer needs local logic to reinterpret `MOVE/IDLE` as visible stops.
- [ ] Mobile statistics for stop count, stopped time and movement time match the backend projection for trips with virtual stops.
- [ ] Existing significant-place and stop labels still render correctly in mobile detail.
- [ ] Mobile tests cover visible stop rendering and statistics using backend payloads that include virtual stops.

## Blocked by

- [Align diary and export APIs to the backend stop projection](04-align-diary-and-export-apis-to-the-backend-stop-projection.md)
