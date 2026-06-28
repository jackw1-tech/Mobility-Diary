# Mappa Di Frequentazione — Heatmap Dei Luoghi Significativi

Status: ready-for-agent

## Parent

.scratch/personal-analytics/PRD.md

## What to build

The Mappa di Frequentazione section of the Analitiche Personali screen: a heatmap
of the user's most frequented Luoghi Significativi, cumulative over all history
and independent of the Giorno/Settimana toggle.

The endpoint returns the user's Luoghi Significativi as heatmap points: precise
owner-facing coordinates plus a visit-frequency weight derived from visit count /
distinct days. Mobile renders these as a weighted Mapbox heatmap layer in a map
panel, reusing the existing Mapbox integration, so that frequently visited places
glow more intensely. When the user has no places yet, the section shows its own
empty state instead of a blank map.

The data is the owner's precise personal data (no privacy-aware reduction); the
endpoint stays user-scoped.

## Acceptance criteria

- [ ] The endpoint returns cumulative heatmap points with coordinates and a visit-frequency weight per Luogo Significativo.
- [ ] Heatmap weights reflect how often each place is visited (visit count / distinct days).
- [ ] The heatmap data is cumulative over all history and unaffected by the Giorno/Settimana toggle.
- [ ] The screen renders a weighted Mapbox heatmap panel where more frequent places are more intense.
- [ ] The section shows a dedicated empty state when the user has no Luoghi Significativi.
- [ ] The map panel matches the flat visual style of the screen.
- [ ] Backend test (HTTP endpoint seam) covers heatmap point weights and user scoping.
- [ ] Mobile presenter test covers mapping the DTO into heatmap points and the empty-state flag.

## Blocked by

- .scratch/personal-analytics/issues/01-analitiche-personali-walking-skeleton.md
