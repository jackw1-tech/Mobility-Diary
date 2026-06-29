# Andamento Recente — Grafico Tempo Per Categoria E Distanze Finestrate

Status: ready-for-agent

## Parent

.scratch/personal-analytics/PRD.md

## What to build

The "Andamento recente" section of the Analitiche Personali screen: a stacked bar
chart of time spent per Categoria di Mobilita, driven by a Giorno/Settimana
Finestra Analitica toggle, plus a distances card for the selected window.

The endpoint gains a granularity selector (Giorno = last 7 days as 7 daily
buckets, Settimana = last 8 weeks as 8 weekly buckets) and the device's local
timezone, used to assign each Segmento di Mobilita to the local day of its start
timestamp (no midnight splitting). Each bucket carries per-Categoria di Mobilita
seconds and per-category movement distance. Categories map one-to-one from the
Etichetta di Attivita: IDLE -> Fermo, WALKING -> A piedi, RUNNING -> Corsa,
BIKING -> In bici, MOVING_VEHICLE -> In auto.

Mobile: add the fl_chart dependency and render a stacked bar chart (themed to the
flat ColorPalette) with a period-labelled axis and a category legend, a
segmented Giorno/Settimana toggle that re-scopes both the chart and the distances
card, and a distances card showing the window total plus the per-category
breakdown with an "In movimento" derived total (sum of non-Fermo categories).

## Acceptance criteria

- [ ] The endpoint accepts a granularity parameter (day | week) and a device local timezone.
- [ ] Day granularity returns the last 7 daily buckets; week granularity returns the last 8 weekly buckets.
- [ ] Each bucket carries per-Categoria di Mobilita seconds and per-category distance.
- [ ] Buckets are computed in the supplied local timezone, assigning a segment to the local day of its start timestamp.
- [ ] Categoria di Mobilita is derived one-to-one from the Etichetta di Attivita as specified.
- [ ] The screen shows a stacked bar chart of time per Categoria di Mobilita with a period-labelled axis and a category legend.
- [ ] A Giorno/Settimana toggle re-scopes both the chart and the distances card.
- [ ] The distances card shows the window total and a per-category breakdown, with "In movimento" as the derived non-Fermo total.
- [ ] The chart and card match the flat visual style.
- [ ] Backend test (HTTP endpoint seam) covers day and week bucketing, timezone assignment, and per-category seconds/distance.
- [ ] Mobile presenter test covers mapping a windowed DTO into chart series, the derived "In movimento" total, and formatted distances.

## Blocked by

- .scratch/personal-analytics/issues/01-analitiche-personali-walking-skeleton.md

## Comments

Implemented (local, no GitHub).

Backend: `GET /mobility/analytics?granularity=day|week&tz=<iana>` now fills
`buckets` — day = last 7 daily buckets, week = last 8 weekly buckets — each with
per-Categoria di Mobilita seconds and distance. Segments are bucketed by the
local day of their `start_timestamp` in the supplied timezone (unknown tz falls
back to UTC). Category mapping is one-to-one from the Etichetta di Attivita.
HTTP-seam tests cover day/week shape, per-category seconds+distance, local-midnight
boundary bucketing, and the tz fallback.

Mobile: added `fl_chart`. Pure `buildAnalyticsTrend` presenter maps the DTO into
chart bars (seconds per category, aligned to `kMobilityCategories`), the derived
"In movimento" total (sum of non-Fermo time), total distance, and per-category
totals. `AnalyticsPage` ready state now renders a Giorno/Settimana SegmentedButton
(re-scoping via the cubit), a stacked bar chart + legend, and a distances card.
Presenter-seam tests cover series alignment, the movement total, and distances.

Also removed an orphaned `started_at` assertion in
`test_inline_core_ingestion_api.py` left from reverted work.
