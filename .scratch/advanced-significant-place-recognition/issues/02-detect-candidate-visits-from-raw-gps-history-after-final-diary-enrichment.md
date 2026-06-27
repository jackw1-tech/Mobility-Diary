# Detect candidate visits from raw GPS history after final diary enrichment

Status: ready-for-human

## Parent

- [PRD: Advanced Significant Place Recognition](../PRD.md)

## What to build

Add raw-GPS permanence detection that runs after final diary enrichment and
recomputes visits against the full history of one Proprietario del Viaggio.

This slice should filter poor-accuracy points, detect permanence episodes from
raw `GpsPoint` history using the agreed distance-plus-time heuristic, require
at least three valid points, tolerate only bounded gaps, and persist the
resulting `Visite Candidate`. The mining flow must be serialized per user so
two trips finishing close together cannot race.

The completed slice is demoable when a processed user with repeated or single
stops ends up with persisted candidate visits derived only from raw GPS.

## Acceptance criteria

- [ ] After final HAR enrichment of a Viaggio, the backend recomputes candidate visits from the full raw GPS history of that user.
- [ ] Candidate visits are created only from permanence episodes that satisfy the agreed thresholds and point-quality rules.
- [ ] Significant-place mining is serialized per user so concurrent trip completions do not create conflicting candidate visits.

## Blocked by

- [01-introduce-user-scoped-significant-place-domain-and-remove-trip-scoped-discovery.md](./01-introduce-user-scoped-significant-place-domain-and-remove-trip-scoped-discovery.md)

## Comments

- Done. New `CandidateVisit` model + migration `0011`. New seam
  `mobility/significant_places.py`: pure `detect_visits` (distance+time stay
  detection, centroide aggiornato, accuracy filter, gap tolerance = min
  permanence so a minimal 5-min/3-point stay is never split) and
  `mine_user_significant_places(user_id)` (full per-user recompute, serialized
  with `pg_advisory_xact_lock` per ADR 0026/0027). Hooked after final enrichment
  in both HAR success paths via `_schedule_place_mining` → Celery
  `mine_significant_places` task (`tasks.py`). Shared `geo.haversine_meters`
  (`geo.py`) now also used by the pipeline (removed its duplicate `_haversine`).
  Tests in `test_significant_places.py` (detector + orchestrator) and a HAR-final
  scheduling test. Serialization is smoke-covered (lock SQL runs in every mining
  test) + behaviourally via user-isolation/idempotent-recompute tests; true
  concurrency isn't unit-tested to avoid flakiness.
