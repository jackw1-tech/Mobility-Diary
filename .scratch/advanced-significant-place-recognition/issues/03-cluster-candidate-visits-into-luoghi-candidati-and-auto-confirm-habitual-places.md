# Cluster candidate visits into Luoghi Candidati and auto-confirm habitual places

Status: ready-for-human

## Parent

- [PRD: Advanced Significant Place Recognition](../PRD.md)

## What to build

Cluster persisted `Visite Candidate` into `Luoghi Candidati` with DBSCAN and
auto-confirm habitual places after recurring evidence on three distinct days.

This slice should group compatible visits for the same user into one place
hypothesis, expose the cluster-level state needed by later review UIs, and
promote a place automatically once it accumulates enough distinct-day evidence.
The result should remain user-scoped and should not require any manual review
to start producing confirmed places.

## Acceptance criteria

- [ ] The backend groups compatible candidate visits into user-scoped Luoghi Candidati using DBSCAN.
- [ ] A Luogo Candidato becomes automatically confirmed after evidence across at least three distinct days.
- [ ] The resulting place read model exposes enough state to distinguish at least candidate and confirmed places.

## Blocked by

- [02-detect-candidate-visits-from-raw-gps-history-after-final-diary-enrichment.md](./02-detect-candidate-visits-from-raw-gps-history-after-final-diary-enrichment.md)

## Comments

- Done. Hand-rolled `_dbscan` (no sklearn/scipy in the env; ADR 0022 favors an
  explainable DBSCAN) over visit centroids, eps = stay radius (75 m),
  min_samples = 2 so a one-off visit stays noise (no place). `_build_place`
  derives center/radius/visit_count/distinct_days and auto-confirms at >= 3
  distinct days (CONFIRMED) else CANDIDATE — populating the read-model state on
  `HabitualPlace`. Clustering runs inside `mine_user_significant_places` (full
  recompute: places deleted+rebuilt per run) and links member `CandidateVisit`
  rows via the new `place` FK (migration `0012`) as map evidence for issue 05.
  Tests added in `test_significant_places.py` (DBSCAN pure + auto-confirm/area
  separation/visit-linking). No manual-review preservation yet — that's issue 07.
