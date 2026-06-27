# Cluster candidate visits into Luoghi Candidati and auto-confirm habitual places

Status: ready-for-agent

## Parent

- [PRD: Advanced Significant Place Recognition](../PRD.md)

## What to build

Cluster persisted `Visite Candidate` into `Luoghi Candidati` with DBSCAN and
auto-confirm habitual places after recurring evidence on three distinct days.

This slice should group compatible visits for the same user into one place
hypothesis, expose the cluster-level state needed by later review UIs, and
promote a place automatically once it accumulates enough distinct-day evidence.
The result should remain user-scoped and should not require any manual review
to start producing confirmed places.

## Acceptance criteria

- [ ] The backend groups compatible candidate visits into user-scoped Luoghi Candidati using DBSCAN.
- [ ] A Luogo Candidato becomes automatically confirmed after evidence across at least three distinct days.
- [ ] The resulting place read model exposes enough state to distinguish at least candidate and confirmed places.

## Blocked by

- [02-detect-candidate-visits-from-raw-gps-history-after-final-diary-enrichment.md](./02-detect-candidate-visits-from-raw-gps-history-after-final-diary-enrichment.md)
