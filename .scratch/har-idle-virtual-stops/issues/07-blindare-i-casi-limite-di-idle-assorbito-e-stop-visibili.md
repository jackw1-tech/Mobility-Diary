# Blindare i casi limite di idle assorbito e stop visibili

Status: ready-for-human

## Parent

- [PRD: HAR Idle Virtual Stops and Unified Diary Projection](../PRD.md)

## What to build

Close the remaining edge cases so the simplified stop model stays stable across
all visible product surfaces.

This slice should verify and, where needed, refine the end-to-end behavior for:
initial short `HAR IDLE` absorbed into the following activity, no visible
`MOVE/IDLE`, correct merge between real and virtual stops, and parity across
backend diary APIs, mobile detail and web dashboard.

The end-to-end result should be that the user sees one consistent story
everywhere even on messy trips with mixed stop evidence.

## Acceptance criteria

- [ ] A trip that starts with short `HAR IDLE` shows that interval absorbed into the first following activity rather than as a visible stop.
- [ ] No visible diary surface exposes a final `MOVE/IDLE` segment.
- [ ] Real and virtual stops that are adjacent across backend, mobile and web appear as one visible stop with matching duration.
- [ ] The same trip yields matching visible stop semantics in backend diary APIs, mobile trip detail and the web dashboard.
- [ ] Automated tests cover these parity and edge-case behaviors end-to-end.

## Blocked by

- [Consume the backend stop projection in mobile trip detail](05-consume-the-backend-stop-projection-in-mobile-trip-detail.md)
- [Consume the backend stop projection in the web dashboard](06-consume-the-backend-stop-projection-in-the-web-dashboard.md)

## Comments

- This slice ended up being mostly a hardening pass, not a product-code refactor.
  The core pipeline/projection/client seams were already behaving correctly
  after issues 02-06, so the work focused on adding explicit regression tests
  for the remaining edge cases.
- Added a mobile-diary API test proving that a trip starting with short
  `HAR IDLE` is shown as one following `MOVE` after final enrichment, with no
  visible stop created.
- Added a mobile-diary API test proving that a real `STOP` adjacent to a
  `VirtualStopInterval` is exposed as one merged visible stop with the expected
  boundaries and no final visible `MOVE/IDLE`.
- Added the matching web-dashboard backend test for the same
  real-stop + virtual-stop scenario, asserting the same visible timeline
  semantics and the absence of `MOVE/IDLE`.
- Added client-side parity tests on both mobile and web summary utilities for a
  backend-projected trip shaped as:
  `MOVE -> merged STOP -> MOVE`, so stop count / stopped time stay aligned
  across surfaces.
- Simplification pass applied after implementation:
  no new product logic was introduced; we kept the hardening entirely in tests
  and only added tiny timestamp helpers in test files to align with the API's
  millisecond JSON serialization.
- Verification:
  - `flutter test test/ui/pages/trip_diary_presenter_test.dart`
  - `npm test`
  - `../.venv/bin/pytest --reuse-db mobility/tests/test_trip_track.py -q -k "diary_endpoint_absorbs_initial_short_idle_into_following_move or diary_endpoint_merges_adjacent_real_and_virtual_stop_without_visible_move_idle"`
  - `../.venv/bin/pytest --reuse-db accounts/tests/test_web_users_api.py -q -k "trip_dashboard_merges_adjacent_real_and_virtual_stop"`
