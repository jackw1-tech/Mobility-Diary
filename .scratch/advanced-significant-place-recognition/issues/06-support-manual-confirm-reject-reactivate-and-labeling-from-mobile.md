# Support manual confirm, reject, reactivate, and labeling from mobile

Status: ready-for-human

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

## Comments

- Done. Backend: `manually_reviewed` flag (migration `0013`) + four endpoints
  `POST /places/{id}/{confirm,reject,reactivate,label}` (`_save_review` helper;
  label validates the closed category set, 422 otherwise). Mining now preserves
  manually-reviewed places across the full recompute (`_place_for_cluster`
  reattaches a nearby manual place instead of recreating it; non-manual places
  are deleted+rebuilt) — so rejected places stay frozen and don't resurface, and
  labels/confirmations survive. Mobile: service action methods, `PlaceDetailCubit`
  (+state), detail page action bar (Conferma/Rifiuta/Riattiva/Etichetta) with a
  category-dropdown + name label dialog, list gains a Rifiutati section and
  reloads on return. Simplify: unified the service GET/POST helpers into one
  `_send`. Tests: backend action/scoping/validation + recompute-freeze/label-
  survival; mobile `PlaceDetailCubit`. Issue 07 will add the overlay tie-break
  (manual label wins) + regression hardening.
