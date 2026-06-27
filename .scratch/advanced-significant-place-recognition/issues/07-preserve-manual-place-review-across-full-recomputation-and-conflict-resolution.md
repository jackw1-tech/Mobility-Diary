# Preserve manual place review across full recomputation and conflict resolution

Status: ready-for-agent

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
