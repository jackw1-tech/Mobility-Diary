# Abitudini Di Sempre — Modalità Prevalente E Percorsi Frequenti

Status: ready-for-agent

## Parent

.scratch/personal-analytics/PRD.md

## What to build

The "Abitudini di sempre" section of the Analitiche Personali screen: the user's
prevalent mobility mode and their Percorsi Frequenti, both cumulative over all
history and independent of the Giorno/Settimana toggle.

The endpoint returns the prevalent Categoria di Mobilita (the category with the
greatest total time over all history, excluding Fermo from the prevalent travel
mode) and the top Percorsi Frequenti. A Percorso Frequente is an ordered pair
(origin Luogo Significativo -> destination Luogo Significativo): for each Viaggio,
the start and end of its trajectory are matched to the nearest Luogo Significativo
within that place's radius_meters (fallback threshold 150 m); the pair's frequency
is the count of Viaggi matching it. Viaggi without a match at both ends are
excluded. Pairs are returned with human-readable place labels, ordered by
frequency.

Mobile renders a prevalent-mode tile and a Percorsi Frequenti list showing each
"Origine -> Destinazione" pair with its Viaggi count, ordered by frequency, with a
dedicated empty state when no journeys match.

## Acceptance criteria

- [ ] The endpoint returns the prevalent Categoria di Mobilita by greatest total time over all history, excluding Fermo.
- [ ] The endpoint returns top Percorsi Frequenti as ordered origin -> destination pairs between Luoghi Significativi.
- [ ] Trip endpoints are matched to the nearest Luogo Significativo within radius_meters (fallback 150 m); Viaggi unmatched at both ends are excluded.
- [ ] Each Percorso Frequente carries its Viaggi count and human-readable origin/destination labels, ordered by frequency.
- [ ] Prevalent mode and Percorsi Frequenti are cumulative and unaffected by the Giorno/Settimana toggle.
- [ ] The screen shows a prevalent-mode tile and a Percorsi Frequenti list.
- [ ] The section shows a dedicated empty state when no journeys match.
- [ ] The tile and list match the flat visual style.
- [ ] Backend test (HTTP endpoint seam) covers prevalent-mode selection, O->D matching and counting, exclusion of unmatched Viaggi, and ordering.
- [ ] Mobile presenter test covers mapping the DTO into the prevalent-mode label, route labels with counts, and the empty-state flag.

## Blocked by

- .scratch/personal-analytics/issues/01-analitiche-personali-walking-skeleton.md
