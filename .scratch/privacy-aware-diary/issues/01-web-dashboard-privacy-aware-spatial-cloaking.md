# Web Dashboard: Vista Privacy-Aware Con Spatial Cloaking Base

Status: ready-for-human

## Parent

.scratch/privacy-aware-diary/PRD.md

## What to build

Build the first end-to-end Vista Privacy-Aware for the web Dettaglio Viaggio. For a single Viaggio, the backend should generate a privacy-aware read model from the stored Vista Privata del Diario by applying deterministic metric-grid spatial cloaking to the Traiettoria del Viaggio and Segmento di Mobilita paths. The Piattaforma Web should render the private trace and the privacy-aware trace on the same comparison map, with a simple layer toggle for private, privacy-aware, and both.

This slice is the foundation for the rest of the privacy work. It does not need all three Livelli Privacy yet, full metrics, significant-place masking, or mobile export. It should prove that the system can generate and display a cloaked geometry without persisting a second perturbed copy of the Viaggio.

## Acceptance criteria

- [ ] The web Dettaglio Viaggio response includes a privacy-aware block for the selected/default privacy level.
- [ ] The privacy-aware block includes a map-ready cloaked Traiettoria del Viaggio.
- [ ] Movement Segmenti di Mobilita keep their original time intervals and Etichette di Attivita, but expose cloaked paths in the privacy-aware view.
- [ ] The cloaking transformation is deterministic for the same coordinate and same level.
- [ ] The cloaking grid is metric and global, not a Bologna-specific bounding box and not plain decimal truncation.
- [ ] Consecutive duplicate cloaked cell centers may be collapsed for display without changing the underlying private diary.
- [ ] The web map can show private trace, privacy-aware trace, or both.
- [ ] Backend tests cover the web read model contract and prove that privacy-aware geometry differs from precise geometry for a non-precise level.
- [ ] Frontend tests or equivalent UI verification cover that the dashboard renders the privacy-aware layer without removing the private comparison.

## Blocked by

None - can start immediately
