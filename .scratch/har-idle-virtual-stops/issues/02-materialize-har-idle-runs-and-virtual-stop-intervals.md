# Materialize HAR idle runs and virtual stop intervals

Status: ready-for-agent

## Parent

- [PRD: HAR Idle Virtual Stops and Unified Diary Projection](../PRD.md)

## What to build

Introduce the derived backend evidence needed to simplify `HAR IDLE` handling
without falsifying the structural diary model.

This slice should group consecutive HAR `IDLE` predictions into `HAR Idle Runs`
during final trip enrichment and apply the product rule:

- if the run lasts less than 2 minutes, absorb it into the previous non-idle
  activity;
- if no previous non-idle activity exists, absorb it into the first following
  non-idle activity;
- if the run lasts at least 2 minutes, persist it as a `Virtual Stop Interval`
  tied to the trip as derived evidence.

The end-to-end result should be that final trip processing no longer leaves
behind visible `MOVE/IDLE` ambiguity and has the raw material needed for a
backend stop projection.

Implementation detail that should be treated as part of the contract:

- a `Virtual Stop Interval` is just temporal stop evidence;
- it has start and end timestamps and trip ownership;
- it is not itself a visible diary card yet;
- it will later be merged by the backend projection together with persisted
  `STOP` segments into a final `Visible Stop`.

## Acceptance criteria

- [ ] Final HAR enrichment groups consecutive `IDLE` predictions into deterministic idle runs.
- [ ] `HAR IDLE` runs shorter than 2 minutes are absorbed into neighboring non-idle activity, preferring the previous activity and falling back to the next one when needed.
- [ ] `HAR IDLE` runs of at least 2 minutes persist backend evidence as `Virtual Stop Interval` rather than as fake `StateTransition` or `MobilitySegment` rows.
- [ ] The persisted structural diary model remains based on real `MOVE` and `STOP` segments.
- [ ] `Virtual Stop Interval` persistence is documented and testable as derived stop evidence, not as final timeline output.
- [ ] Backend tests cover short-idle absorption, initial-idle fallback to the next activity, and long-idle materialization as virtual-stop evidence.

## Blocked by

- [Simplify the acquisition FSM to movement and stationary](01-simplify-the-acquisition-fsm-to-movement-and-stationary.md)
