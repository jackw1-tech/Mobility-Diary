# Detect candidate visits from raw GPS history after final diary enrichment

Status: ready-for-agent

## Parent

- [PRD: Advanced Significant Place Recognition](../PRD.md)

## What to build

Add raw-GPS permanence detection that runs after final diary enrichment and
recomputes visits against the full history of one Proprietario del Viaggio.

This slice should filter poor-accuracy points, detect permanence episodes from
raw `GpsPoint` history using the agreed distance-plus-time heuristic, require
at least three valid points, tolerate only bounded gaps, and persist the
resulting `Visite Candidate`. The mining flow must be serialized per user so
two trips finishing close together cannot race.

The completed slice is demoable when a processed user with repeated or single
stops ends up with persisted candidate visits derived only from raw GPS.

## Acceptance criteria

- [ ] After final HAR enrichment of a Viaggio, the backend recomputes candidate visits from the full raw GPS history of that user.
- [ ] Candidate visits are created only from permanence episodes that satisfy the agreed thresholds and point-quality rules.
- [ ] Significant-place mining is serialized per user so concurrent trip completions do not create conflicting candidate visits.

## Blocked by

- [01-introduce-user-scoped-significant-place-domain-and-remove-trip-scoped-discovery.md](./01-introduce-user-scoped-significant-place-domain-and-remove-trip-scoped-discovery.md)
