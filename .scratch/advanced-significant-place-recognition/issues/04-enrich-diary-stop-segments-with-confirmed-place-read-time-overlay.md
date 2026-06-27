# Enrich diary STOP segments with confirmed place read-time overlay

Status: ready-for-human

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

## Comments

- Done. `get_trip_diary` now overlays Confirmed `HabitualPlace`s onto STOP
  segments at read time: each stop derives its position from the GpsPoint in its
  interval (`_stop_centroid`) and takes the closest confirmed place within
  `OVERLAY_MATCH_METERS` (`match_confirmed_place`). `place_label` resolves
  custom_name > category > "luogo abituale" (ADR 0023). MOVE segments and
  persisted `MobilitySegment` rows are untouched (asserted: stop `place_id`
  stays None after a read). `PlaceOut` reshaped to {id, lat, lon, label,
  category}. Simplify: removed the now-dead trip-scoped place merging
  (`_merge_place` + `place` field) from `diary_projection.py`. Tests rewritten in
  `test_trip_track.py` (labeled/neutral/closest/candidate-ignored/merge) + pure
  matcher/label tests in `test_significant_places.py`. The old trip-scoped
  `SignificantPlace` model + `MobilitySegment.place` FK survive only for the
  separate privacy-export view (out of this PRD's scope).
