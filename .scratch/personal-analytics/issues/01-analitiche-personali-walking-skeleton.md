# Analitiche Personali — Walking Skeleton End-To-End

Status: ready-for-agent

## Parent

.scratch/personal-analytics/PRD.md

## What to build

The thinnest complete path through every layer for the new Analitiche Personali
surface, so that the next slices only add sections to an already-working pipeline.

From the Home, a new AppBar action opens a dedicated Analitiche Personali screen.
The screen loads a single user-scoped mobile endpoint (mobile bearer auth) that
returns the full Analitiche Personali payload shape, and renders the cross-cutting
states: loading, error (with retry), empty (no synced Viaggi), and a ready state.
Pull-to-refresh re-requests the endpoint.

This slice establishes the endpoint and its response *shape* (windowed buckets
plus cumulative aggregates, even if sections are returned empty/zero here), the
navigation route, and the mobile service / DTO / cubit / presenter scaffolding,
following the existing trips and privacy-export conventions. Later slices fill in
the chart, heatmap, and habit sections behind this same endpoint and screen.

The endpoint aggregates backend-side (ADR 0030); it must be user-scoped and must
not leak another user's data. Use the domain vocabulary from CONTEXT.md
(Analitiche Personali, Categoria di Mobilita, Finestra Analitica, Mappa di
Frequentazione, Percorso Frequente).

## Acceptance criteria

- [ ] A new user-scoped mobile endpoint returns the Analitiche Personali payload with bearer auth.
- [ ] The endpoint response carries the full shape: windowed buckets plus cumulative aggregate sections (may be empty/zero in this slice).
- [ ] The endpoint is scoped to the authenticated user and never returns another user's data.
- [ ] An empty history returns a well-formed empty payload (not an error).
- [ ] A new route hosts the Analitiche Personali screen, reachable from an AppBar action on the Home.
- [ ] The screen loads the endpoint on open and exposes loading, error (with retry), empty, and ready states.
- [ ] Pull-to-refresh re-requests the endpoint.
- [ ] The screen matches the existing flat visual style (ColorPalette / Dimensions panels).
- [ ] Backend test (HTTP endpoint seam) covers the contract, user scoping, and the empty-history response.
- [ ] Mobile cubit test covers load / refresh / error / empty transitions against a fake service.

## Blocked by

None - can start immediately.
