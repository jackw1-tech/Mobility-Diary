# Simplify the acquisition FSM to movement and stationary

Status: ready-for-human

## Parent

- [PRD: HAR Idle Virtual Stops and Unified Diary Projection](../PRD.md)

## What to build

Reduce the acquisition state machine to the only two domain states that matter
for trip semantics: `movement` and `stationary`.

This slice should remove `potentialMotion` and `activeTracking` as first-class
FSM states and replace them with internal confirmation or debounce logic where
needed. The end-to-end result should be that mobile acquisition, synced
`StateTransition` rows and backend trip segmentation all reason in terms of the
same simple state vocabulary, while preserving the practical ability to avoid
noisy flapping.

## Acceptance criteria

- [ ] The acquisition FSM exposes only `movement` and `stationary` as domain states.
- [ ] Any motion-confirmation grace periods, counters or timers remain internal implementation details rather than synced/public states.
- [ ] Synced `StateTransition` rows represent only changes between `movement` and `stationary`.
- [ ] Existing trip acquisition and segmentation behavior remains functional after the FSM simplification.
- [ ] Mobile-domain and backend-oriented tests cover the two-state behavior and the absence of old intermediate states.

## Blocked by

None - can start immediately

## Comments

- Done. The mobile acquisition FSM now exposes only `STATIONARY` and
  `MOVEMENT`.
- Removed `potentialMotion`, `activeTracking`, the timeout event, and the
  repository timer that existed only to support the intermediate state.
- Simplified `FsmConfig` by removing the potential-motion and fast-speed
  branches; movement confirmation now comes from:
  consecutive motion windows or repeated moving GPS fixes.
- Sampling profiles were reduced to stationary/deep-stationary plus one
  movement profile.
- Synced transition fixtures were updated from `ACTIVE_TRACKING` /
  `POTENTIAL_MOTION` to `MOVEMENT` in mobile tests and backend ingestion /
  pipeline tests.
- Complexity pass: net reduction of several hundred lines across FSM +
  repository + tests. The new FSM file is substantially shorter and the
  repository no longer owns state-timeout plumbing.
- Verification:
  `flutter test` on the affected mobile acquisition/domain/sync suites passed.
  `flutter analyze` on the affected mobile files passed.
  Targeted backend pytest passed except for the known pre-existing HAR-model
  mismatch in `test_process_trip_har_final_reads_raw_and_regenerates_segments`
  (`BIKING` vs `WALKING`), which is unrelated to this state-vocabulary change.
