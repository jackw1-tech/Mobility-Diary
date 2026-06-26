# Metriche Privacy Perturbation E Quality Of Service

Status: ready-for-human

## Parent

.scratch/privacy-aware-diary/PRD.md

## What to build

Add the metric layer that makes the privacy-quality trade-off visible. For each privacy-aware level, the backend should compute Privacy Perturbation as the distance between real positions and their published cell-center positions. It should also compute Quality of Service v1 as relative route-distance error between the private trajectory and the privacy-aware trajectory.

The dashboard should display these metric summaries alongside the map comparison so the project can demonstrate both visual perturbation and quantitative loss of service quality.

## Acceptance criteria

- [ ] The privacy-aware read model includes Privacy Perturbation metrics.
- [ ] Privacy Perturbation includes at least mean and maximum distance.
- [ ] Privacy Perturbation is computed from original points before any display-only duplicate-cell collapse.
- [ ] `precise` produces zero Privacy Perturbation.
- [ ] The privacy-aware read model includes Quality of Service v1 as relative route-distance error.
- [ ] Quality of Service compares private route distance with privacy-aware route distance.
- [ ] The dashboard displays Privacy Perturbation and Quality of Service summaries for the selected preview level.
- [ ] Backend tests cover metric correctness for `precise`, `approximate`, and `aggregated`.
- [ ] UI tests or equivalent verification cover metric display while switching levels.

## Blocked by

- .scratch/privacy-aware-diary/issues/01-web-dashboard-privacy-aware-spatial-cloaking.md
- .scratch/privacy-aware-diary/issues/02-dashboard-privacy-levels-and-preview.md

## Comments

Implemented (local, no GitHub).

- `mobility/privacy.privacy_metrics(geometry, level)` returns a `PrivacyMetrics`
  dataclass: perturbation mean/max + sample count, private/privacy-aware route
  distances, and relative distance error. Perturbation pairs every original
  point with its published cell center *before* the display-only
  duplicate-cell collapse; `precise` yields zero perturbation and zero loss.
- QoS v1 = `abs(private_distance - privacy_distance) / private_distance`
  (guarded against division by zero), computed over the `Trip.path` trajectory.
- Surfaced in the web `privacy_aware.metrics` block
  (`WebPrivacyMetricsOut` -> `privacy_perturbation` + `quality_of_service`).
- Dashboard renders three metric cards (perturbazione media/massima, perdita di
  qualita') via `web/src/utils/privacyDashboard.privacyMetricCards`, refreshed on
  every level switch.
- Tests: `mobility/tests/test_privacy.py`
  (`..._precise_has_zero_perturbation_and_loss`, `..._grow_with_cell_size`),
  API `test_web_trip_dashboard_defaults_to_saved_level_with_metrics_and_masked_places`,
  frontend `privacyMetricCards summarizes perturbation and quality loss`.

Verification: web typecheck/test/build pass; `test_privacy.py` passes. DB-backed
API tests not run (local Postgres down).
