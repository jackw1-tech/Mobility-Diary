---
labels:
  - ready-for-agent
---

# Lista Viaggi Per Proprietario Con Filtri

## Parent

[PRD: Piattaforma Web Staff per il Diario della Mobilita](../prd/web-staff-dashboard.md)

## What to build

From a selected Proprietario del Viaggio, show that user's Viaggi using a staff-only web endpoint. The list must be server-filterable by date range, trip status, processed state, and track availability, so the Operatore Web can narrow down the data before opening a Viaggio.

This slice should preserve the distinction between mobile user-scoped APIs and web staff-global APIs.

## Acceptance criteria

- [ ] The dashboard can navigate from a user row to that user's Viaggi.
- [ ] The web API returns only Viaggi owned by the selected Proprietario del Viaggio.
- [ ] The trip list supports server-side filters for `from`, `to`, `status`, `processed`, and `has_track`.
- [ ] The Vue UI exposes controls to apply and clear those filters.
- [ ] Each Viaggio row shows enough metadata to choose a trip: id, start/end timestamps, status, distance, processed state, and track availability.
- [ ] Empty states are shown for users with no Viaggi or filters with no matches.
- [ ] Direct route refresh keeps the selected user context.
- [ ] Tests cover user scoping, each filter, and unauthorized access through the web API.

## Blocked by

- [Staff Login E Sessione Web](0001-staff-login-e-sessione-web.md)
- [Lista Proprietari Del Viaggio](0002-lista-proprietari-del-viaggio.md)
