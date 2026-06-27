# Consume the backend stop projection in the web dashboard

Status: ready-for-agent

## Parent

- [PRD: HAR Idle Virtual Stops and Unified Diary Projection](../PRD.md)

## What to build

Update the web dashboard to consume the backend-projected timeline instead of
rebuilding stop semantics locally.

This slice should make the web map, timeline and statistics use the same
projected stops returned by the backend, including HAR-derived virtual stops and
merged real/virtual stop durations.

The end-to-end result should be that the dashboard tells the same story as the
mobile app and backend exports, while simplifying frontend utilities that today
collapse stop-like segments on their own.

## Acceptance criteria

- [ ] The web dashboard uses backend-projected stop semantics for timeline rows, map markers and trip statistics.
- [ ] The dashboard no longer needs local logic to reinterpret `MOVE/IDLE` as visible stops.
- [ ] Movement split, stopped time and stop count on the web match backend-projected values for trips with virtual stops.
- [ ] Existing significant-place and privacy-aware stop labels still render correctly in the dashboard.
- [ ] Frontend tests cover timeline and statistics parity for payloads containing virtual stops.

## Blocked by

- [Align diary and export APIs to the backend stop projection](04-align-diary-and-export-apis-to-the-backend-stop-projection.md)
