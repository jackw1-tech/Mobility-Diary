# Dashboard: Livelli Privacy E Preview

Status: ready-for-human

## Parent

.scratch/privacy-aware-diary/PRD.md

## What to build

Complete Livello Privacy handling in the web privacy-aware comparison. The dashboard should use the Proprietario del Viaggio's saved Preferenza Privacy as the initial level, while allowing an Operatore Web to preview `precise`, `approximate`, and `aggregated` without changing the saved preference.

The behavior must map the levels to the agreed spatial cloaking configuration: `precise` is unprotected and unchanged, `approximate` uses 150 meter cells, and `aggregated` uses 400 meter cells. All levels should share the same response shape so the dashboard can switch between them predictably.

## Acceptance criteria

- [ ] The initial dashboard privacy-aware level is derived from the owner's saved Preferenza Privacy.
- [ ] The dashboard offers preview controls for `precise`, `approximate`, and `aggregated`.
- [ ] Selecting a preview level updates the privacy-aware geometry and comparison data without changing the user's saved Preferenza Privacy.
- [ ] `precise` returns unchanged geometry and is clearly represented as unprotected.
- [ ] `approximate` uses 150 meter metric cells.
- [ ] `aggregated` uses 400 meter metric cells.
- [ ] All three levels return the same high-level contract shape for track, diary segments, and privacy metadata.
- [ ] Backend tests cover level mapping and default-from-preference behavior.
- [ ] Frontend tests or equivalent UI verification cover preview selection and layer persistence.

## Blocked by

- .scratch/privacy-aware-diary/issues/01-web-dashboard-privacy-aware-spatial-cloaking.md

## Comments

Implemented (local, no GitHub).

- `GET /api/web/users/{user}/trips/{trip}` now accepts an optional `level` query
  param. Absent -> owner's saved Preferenza Privacy; an invalid value -> HTTP
  400. The saved preference is never mutated by a preview. `_resolve_privacy_level`
  in `accounts/web_users_api.py`.
- The `privacy_aware` block carries both `level` (effective) and `default_level`
  (saved preference) so the dashboard can mark the user's preference while
  previewing another level.
- Level->cell mapping is unchanged and centralized in
  `mobility/privacy.privacy_cell_size_meters` (approximate=150 m, aggregated=400 m,
  precise=no cloaking). All three levels share the same response contract.
- Dashboard (`web/src/views/TripDashboardView.vue`) gains a "Confronto privacy"
  panel with precise/approximate/aggregated preview buttons. Selecting a level
  re-fetches only the `privacy_aware` block (`selectPrivacyLevel`), so private
  geometry, local filters and the saved preference stay put. The saved level is
  flagged with a "Preferenza utente" chip; precise shows a "Non protetto" flag.
- Tests: backend `test_web_trip_dashboard_preview_level_does_not_change_saved_preference`,
  `..._precise_preview_is_unprotected`, `..._rejects_invalid_privacy_level`,
  `..._defaults_to_saved_level_with_metrics_and_masked_places`; frontend
  `web/tests/privacyDashboard.test.mjs` (level options/labels/cell sizes).

Verification: `npm run typecheck`, `npm test`, `npm run build` pass. Backend
DB-backed tests written and collect cleanly but were not executed here because
local Postgres/PostGIS is down (connection refused on :5432); the DB-free
`mobility/tests/test_privacy.py` passes.
