# Blindare i casi limite di idle assorbito e stop visibili

Status: ready-for-agent

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
