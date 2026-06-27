# Introduce user-scoped significant place domain and remove trip-scoped discovery

Status: ready-for-human

## Parent

- [PRD: Advanced Significant Place Recognition](../PRD.md)

## What to build

Create the user-scoped domain foundation for advanced significant-place recognition and remove the old trip-scoped `SignificantPlace` discovery from the diary pipeline.

This slice should establish the new place state model for one
Proprietario del Viaggio at a time, with room for candidate, confirmed and
rejected places, and should eliminate the current path where the final diary
pipeline derives significant places directly from a single Viaggio stop.

The end-to-end result should be that the backend can persist user-scoped place
state without relying on trip-scoped place discovery, while the existing diary
structure remains usable.

## Acceptance criteria

- [ ] The backend persists user-scoped significant-place state independently from a single Viaggio.
- [ ] The final diary pipeline no longer creates trip-scoped significant places as a discovery source.
- [ ] Existing diary behavior remains functional after the old trip-scoped discovery path is removed.

## Blocked by

None - can start immediately

## Comments

- Done. Added user-scoped `HabitualPlace` model (states CANDIDATE/CONFIRMED/REJECTED,
  geometry, evidence counters, closed category + optional name) in
  `mobility/models.py` + migration `0010_habitualplace`. Removed trip-scoped
  `SignificantPlace` creation from `ml/pipeline.py` (`_build_stop` no longer mines
  places; dead `_centroid`/threshold/imports dropped, net −22 lines). The old
  trip-scoped `SignificantPlace` model stays only as a read-model FK so the diary
  keeps working; it will be retired once the issue-04 read-time overlay replaces it.
  Tests: `tests/test_significant_places.py`.
