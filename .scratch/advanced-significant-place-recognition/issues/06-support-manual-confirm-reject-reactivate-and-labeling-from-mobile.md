# Support manual confirm, reject, reactivate, and labeling from mobile

Status: ready-for-agent

## Parent

- [PRD: Advanced Significant Place Recognition](../PRD.md)

## What to build

Complete the mobile review flow with manual confirm, reject, reactivate, and
labeling actions backed by persistent review state.

This slice should let the user promote a place manually before automatic
confirmation, reject a false positive, reactivate a previously rejected place,
and assign both a category and an optional custom name. The resulting manual
state must immediately affect the diary overlay and the places screen.

## Acceptance criteria

- [ ] The mobile place-review flow supports confirm, reject, reactivate and manual labeling actions end-to-end.
- [ ] Manual labeling stores a closed category and an optional custom name and takes priority over automatic wording.
- [ ] Rejected places disappear from automatic resurfacing and remain frozen until the user explicitly reactivates them.

## Blocked by

- [05-add-mobile-place-review-screen-for-candidates-and-confirmed-places.md](./05-add-mobile-place-review-screen-for-candidates-and-confirmed-places.md)
