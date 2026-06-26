# Luoghi Significativi Privacy-Aware E Masking Semantico

Status: ready-for-human

## Parent

.scratch/privacy-aware-diary/PRD.md

## What to build

Extend the Vista Privacy-Aware to cover Luoghi Significativi. Their centers should be spatially cloaked with the same metric-grid technique used for tracks and Segmenti di Mobilita. For `approximate` and `aggregated`, the privacy-aware representation must not expose sensitive semantic labels such as home, work, university, or equivalent inferred labels. Instead, stops should use generic wording suitable for a shareable diary.

The private comparison may still show private labels when the private view is inspected. The privacy-aware view itself must not leak those labels.

## Acceptance criteria

- [ ] Privacy-aware Luoghi Significativi use cloaked centers for non-precise levels.
- [ ] The same cloaking service/configuration is used for tracks, movement segments, and significant places.
- [ ] `approximate` and `aggregated` privacy-aware outputs mask sensitive significant-place labels.
- [ ] Masked stops use generic shareable wording.
- [ ] The private comparison can still expose private labels where the existing private dashboard already does so.
- [ ] The privacy-aware dashboard representation does not leak masked labels through map markers, timeline details, tooltips, or export-ready text fields.
- [ ] Backend tests cover cloaked centers and masked labels.
- [ ] UI tests or equivalent verification cover generic stop display in the privacy-aware dashboard.

## Blocked by

- .scratch/privacy-aware-diary/issues/01-web-dashboard-privacy-aware-spatial-cloaking.md
- .scratch/privacy-aware-diary/issues/02-dashboard-privacy-levels-and-preview.md

## Comments

Implemented (local, no GitHub).

- New `mobility/privacy.cloak_point` reuses the exact metric grid used for the
  tracks/segments, so a place center collapses to the same cell center the
  trajectory would. `point_geojson` mirrors `line_geojson`.
- The web `privacy_aware` block gains `significant_places`: cloaked center +
  masked label for non-precise levels (shared constant
  `PRIVACY_AWARE_STOP_LABEL = "Sosta significativa in area approssimata"`),
  real label + real center only for `precise`. The private `diary` block keeps
  its existing behaviour (it never exposed place labels).
- Dashboard draws privacy-aware places as teal `circleMarker`s and lists them in
  the privacy panel; the tooltip/list bind the already-masked label from the API,
  so no sensitive name can leak through markers, timeline or tooltips.
- Same masking constant is reused by the mobile export (issue 05), keeping web
  and mobile wording consistent.
- Tests: API `..._defaults_to_saved_level_with_metrics_and_masked_places`
  (cloaked center + generic label + `"casa" not in payload`) and
  `..._precise_preview_is_unprotected` (real label/center for precise);
  `test_cloak_point_*` in `mobility/tests/test_privacy.py`.

Verification: web typecheck/test/build pass; `test_privacy.py` passes. DB-backed
API tests not run (local Postgres down).
