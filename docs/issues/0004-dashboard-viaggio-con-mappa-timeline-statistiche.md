---
labels:
  - ready-for-agent
---

# Dashboard Viaggio Con Mappa, Timeline E Statistiche

## Parent

[PRD: Piattaforma Web Staff per il Diario della Mobilita](../prd/web-staff-dashboard.md)

## What to build

Build the main Viaggio detail dashboard for an Operatore Web. The page should be a single desktop-oriented dashboard with breadcrumb context, Leaflet/OpenStreetMap map, timeline, and statistics for the open Viaggio.

The map should show the full route and movement segments color-coded by activity. STOP segments should appear neutrally in the timeline but must not create place markers or imply that the Luogo Significativo feature is complete.

## Acceptance criteria

- [ ] Clicking a Viaggio opens a routeable detail page for that trip.
- [ ] The page breadcrumb includes the Proprietario del Viaggio identity and trip id.
- [ ] The dashboard loads track and diary data through staff-only web endpoints.
- [ ] The Leaflet map shows the full trip trace when available.
- [ ] MOVE segments are drawn with functional colors by activity.
- [ ] STOP segments are not rendered as significant-place markers on the map.
- [ ] The timeline shows MOVE and STOP segments with Italian labels, timestamps, durations, distance for movement, and neutral "Sosta rilevata" wording for stops.
- [ ] Statistics summarize only the open Viaggio: total duration, movement time, stopped time, total movement distance, and activity split.
- [ ] The page uses lightweight Uber-inspired styling: monochrome dashboard chrome with functional activity colors only where needed.
- [ ] Tests cover staff access to any user's trip, denial for unauthorized access, and diary/track response shape.

## Blocked by

- [Staff Login E Sessione Web](0001-staff-login-e-sessione-web.md)
- [Lista Proprietari Del Viaggio](0002-lista-proprietari-del-viaggio.md)
- [Lista Viaggi Per Proprietario Con Filtri](0003-lista-viaggi-per-proprietario-con-filtri.md)
