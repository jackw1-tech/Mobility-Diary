# Simplify the acquisition FSM to movement and stationary

Status: ready-for-agent

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

