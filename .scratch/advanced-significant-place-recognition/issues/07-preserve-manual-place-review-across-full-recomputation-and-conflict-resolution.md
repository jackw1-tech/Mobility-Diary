# Preserve manual place review across full recomputation and conflict resolution

Status: ready-for-human

## Parent

- [PRD: Advanced Significant Place Recognition](../PRD.md)

## What to build

Harden the feature so full-history recomputation preserves manual review state
and the diary chooses stable place labels in ambiguous cases.

This slice should ensure that labels, confirmations and rejections survive
cluster updates after future trip processing, and it should finalize the
read-time conflict rules so manually labeled places win over purely automatic
ones when proximity is effectively tied.

The completed slice is done when the feature remains stable after repeated trip
processing and does not lose user curation.

## Acceptance criteria

- [ ] Full per-user recomputation preserves manual labels, confirmations and rejections and reattaches them to the updated place hypothesis for the same area.
- [ ] The diary read-time overlay prefers a manually labeled place over a purely automatic one when multiple nearby confirmed places compete.
- [ ] Regression tests cover recomputation stability and conflict resolution without depending on implementation details.

## Blocked by

- [06-support-manual-confirm-reject-reactivate-and-labeling-from-mobile.md](./06-support-manual-confirm-reject-reactivate-and-labeling-from-mobile.md)

## Comments

- Done. Recompute preservation (AC1) was already implemented in issue 06 (manual
  places survive the full recompute and reattach to the nearby cluster). This
  slice adds the overlay conflict resolution (AC2): `match_confirmed_place` now
  gathers all confirmed places within the match radius, and among those
  effectively tied in distance (`OVERLAY_TIE_METERS` = 25 m) prefers a manually
  labeled place over a purely automatic one, otherwise the closest wins.
  Regression tests (AC3, all behavioural): rejected-place freeze, manual
  label/confirmation survival, repeated-recompute stability (no duplication), and
  tie / not-tied conflict resolution.
- Note: the legacy trip-scoped `SignificantPlace` model + `MobilitySegment.place`
  FK were intentionally NOT removed — issue 01 already removed them as a discovery
  source from the diary pipeline (per ADR 0029), but the separate Vista
  Privacy-Aware (`privacy-export`) still uses them as its own intended, tested
  behaviour. Retiring them belongs to a privacy-export change, out of this PRD.
