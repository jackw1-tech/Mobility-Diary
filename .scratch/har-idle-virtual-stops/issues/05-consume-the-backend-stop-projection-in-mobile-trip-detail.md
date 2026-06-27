# Consume the backend stop projection in mobile trip detail

Status: ready-for-human

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

## Comments

- Mobile trip detail now trusts the backend-projected diary timeline directly:
  the diary tab renders `state.diarySegments` as received, and statistics are
  computed from backend `STOP` rows only.
- Removed the local presenter logic that used to reinterpret `MOVE/IDLE` as a
  visible stop and merge nearby stop-like spans with its own 2-minute
  tolerance. Mobile no longer owns stop semantics.
- The map now derives stop markers from backend-projected `STOP` segments that
  carry a place overlay, so virtual/real visible stops can surface on the map
  without a second client-side merge pass.
- Existing stop labels still render as before:
  confirmed place label when present, otherwise neutral `Sosta rilevata`.
- Simplification pass applied after implementation:
  the old `presentableDiarySegments`, `_asStopSegment`, `_mergePlace` and the
  local stop-gap tolerance were deleted entirely, which made the presenter
  shorter and pushed the semantics back to the backend seam where they belong.
- Verification:
  - `flutter test test/ui/pages/trip_diary_presenter_test.dart test/state_management/cubits/trip_track_cubit_test.dart`
  - `flutter analyze lib/ui/pages/trip_diary_presenter.dart lib/ui/pages/trip_diary_tabs.dart lib/ui/pages/trip_map_page.dart`
