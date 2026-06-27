# Enrich diary STOP segments with confirmed place read-time overlay

Status: ready-for-agent

## Parent

- [PRD: Advanced Significant Place Recognition](../PRD.md)

## What to build

Apply confirmed significant-place semantics to the Diario della Mobilita as a
read-time overlay that enriches only `STOP` segments.

This slice should leave persisted `MobilitySegment` rows untouched while making
the diary response smarter: confirmed unlabeled places should render with
neutral wording, and the overlay should choose the best matching place for a
stop by proximity. `MOVE` segments must remain unchanged.

The completed slice is demoable when a user with auto-confirmed places can open
the diary and see stop descriptions improved even before manual review.

## Acceptance criteria

- [ ] Confirmed places enrich only STOP segments in the diary read model, with no segmentation rewrite.
- [ ] Unlabeled confirmed places render with neutral wording such as `luogo abituale`.
- [ ] When multiple confirmed places are nearby, the read-time overlay applies the closest valid match.

## Blocked by

- [03-cluster-candidate-visits-into-luoghi-candidati-and-auto-confirm-habitual-places.md](./03-cluster-candidate-visits-into-luoghi-candidati-and-auto-confirm-habitual-places.md)
