# Add mobile place-review screen for candidates and confirmed places

Status: ready-for-human

## Parent

- [PRD: Advanced Significant Place Recognition](../PRD.md)

## What to build

Add a mobile place-review surface where the Proprietario del Viaggio can browse
candidate and confirmed places, inspect them on a map, and understand why they
were proposed.

This slice should provide one end-to-end review flow through backend APIs and
mobile UI for reading place state, including counts or days of evidence and map
evidence for each place. It does not yet need the full confirm/reject/label
mutation flow, but the user must be able to inspect the discovered places in a
real screen.

## Acceptance criteria

- [ ] The mobile app exposes a dedicated place-review screen with at least candidate and confirmed sections.
- [ ] Opening a place shows its map area and supporting evidence returned by the backend.
- [ ] The place-review read model includes enough context for the user to understand why a place was proposed or confirmed.

## Blocked by

- [03-cluster-candidate-visits-into-luoghi-candidati-and-auto-confirm-habitual-places.md](./03-cluster-candidate-visits-into-luoghi-candidati-and-auto-confirm-habitual-places.md)

## Comments

- Done. Backend `GET /api/mobility/places` returns all user places with context
  (state, visit_count, distinct_days, label) and embedded visit evidence
  (`PlaceReviewOut`/`PlaceVisitOut`), so the mobile detail needs no extra fetch.
  Mobile: `place_review_dto.dart`, `places_service.dart`, `places_cubit` (+state
  with confirmed/candidate/rejected getters), `places_page.dart` (Confermati +
  Candidati sections), `place_detail_page.dart` (Mapbox map: place center + visit
  evidence circles + "why proposed" panel), shared `place_presenter.dart`
  helpers. Routes `/places` + `/places/detail` (auto_route codegen via
  `dart run build_runner build --force-jit`; needed `place_review_dto` imported in
  `app_router.dart` so the generated part sees the arg type). Entry: a place icon
  in the home AppBar. Tests: DTO + cubit. Note: each HTTP service still
  duplicates the request boilerplate (pre-existing codebase convention) — a
  shared json-http helper would cut LOC but is a separate, broader refactor.
