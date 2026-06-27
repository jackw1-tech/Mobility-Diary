# Consume the backend stop projection in the web dashboard

Status: ready-for-human

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

## Comments

- The web dashboard no longer rebuilds stop semantics locally.
  `web/src/utils/tripDashboard.ts` now treats only backend `STOP` rows as
  stops, orders segments by time, and computes stop count / stopped time
  directly from the projected timeline.
- Removed the old frontend merge layer that used to reinterpret `MOVE/IDLE`
  as a visible stop and collapse adjacent stop-like spans. The deleted
  `presentableSegments()` path is now replaced by simple ordering + filtering.
- The dashboard timeline now renders backend stop labels when available
  (`casa`, etc.), otherwise the neutral fallback `Sosta rilevata`.
- The map now draws stop markers from backend-projected diary stops for both
  private and privacy-aware layers, so HAR-derived visible stops and real stops
  share one client contract.
- The privacy-aware diary payload now carries an optional stop `place` too,
  with exact labels/centers for `precise` and masked labels/cloaked centers for
  protected levels. This keeps the dashboard aligned with the mobile detail
  contract and avoids inventing labels client-side.
- Simplification pass applied after implementation:
  removed duplicated frontend stop-merging logic and deleted an unused backend
  helper introduced during the first pass.
- Verification:
  - `npm run typecheck`
  - `npm test`
  - `../.venv/bin/pytest --reuse-db accounts/tests/test_web_users_api.py -q -k "trip_dashboard"`
