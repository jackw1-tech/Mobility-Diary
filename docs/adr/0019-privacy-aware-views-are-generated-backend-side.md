# Privacy-Aware Views Are Generated Backend-Side

## Status

Accepted

## Context

The project must compare a private detailed mobility diary with a shareable
privacy-aware version. The HAR pipeline, segmentation, significant-place
detection, and private diary need precise evidence to produce useful results.

## Decision

Generate privacy-aware diary views backend-side from the stored private diary.
The backend keeps precise trip evidence for HAR and private inspection, then
applies spatial cloaking when serving export, sharing, or dashboard comparison
views.

## Consequences

This protects the published or shareable diary representation, not the raw data
from the backend itself. A future system that treats the backend as untrusted
would need mobile-side perturbation before upload, but that is outside the scope
of this project implementation.
