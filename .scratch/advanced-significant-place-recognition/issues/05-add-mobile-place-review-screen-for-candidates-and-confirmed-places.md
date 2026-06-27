# Add mobile place-review screen for candidates and confirmed places

Status: ready-for-agent

## Parent

- [PRD: Advanced Significant Place Recognition](../PRD.md)

## What to build

Add a mobile place-review surface where the Proprietario del Viaggio can browse
candidate and confirmed places, inspect them on a map, and understand why they
were proposed.

This slice should provide one end-to-end review flow through backend APIs and
mobile UI for reading place state, including counts or days of evidence and map
evidence for each place. It does not yet need the full confirm/reject/label
mutation flow, but the user must be able to inspect the discovered places in a
real screen.

## Acceptance criteria

- [ ] The mobile app exposes a dedicated place-review screen with at least candidate and confirmed sections.
- [ ] Opening a place shows its map area and supporting evidence returned by the backend.
- [ ] The place-review read model includes enough context for the user to understand why a place was proposed or confirmed.

## Blocked by

- [03-cluster-candidate-visits-into-luoghi-candidati-and-auto-confirm-habitual-places.md](./03-cluster-candidate-visits-into-luoghi-candidati-and-auto-confirm-habitual-places.md)
