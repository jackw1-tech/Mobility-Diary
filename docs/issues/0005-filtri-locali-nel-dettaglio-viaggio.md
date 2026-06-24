---
labels:
  - ready-for-agent
---

# Filtri Locali Nel Dettaglio Viaggio

## Parent

[PRD: Piattaforma Web Staff per il Diario della Mobilita](../prd/web-staff-dashboard.md)

## What to build

Complete the Viaggio detail dashboard with client-side filters for activity and time interval. Filtering should update the visible movement segments, timeline rows, and open-trip statistics without requiring additional backend endpoints.

This slice should keep the scope focused on the currently open Viaggio and must not introduce global analytics or privacy-aware comparison.

## Acceptance criteria

- [ ] The detail dashboard provides activity filters for the activity labels present in the open Viaggio.
- [ ] The detail dashboard provides a time-interval filter for the open Viaggio.
- [ ] Filtering updates the timeline rows shown to the Operatore Web.
- [ ] Filtering updates the map's visible MOVE segments while keeping STOP segments off the map.
- [ ] Filtering updates the statistics for the currently visible subset.
- [ ] Clearing filters restores the full Viaggio view.
- [ ] The filters are local to the detail page and do not require new backend query parameters.
- [ ] Frontend tests cover filtering behavior through visible UI and mocked trip data.

## Blocked by

- [Dashboard Viaggio Con Mappa, Timeline E Statistiche](0004-dashboard-viaggio-con-mappa-timeline-statistiche.md)
