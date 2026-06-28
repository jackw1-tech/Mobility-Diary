# PRD: Analitiche Personali

Status: ready-for-agent

> Copia locale per il tracker. Questa PRD sintetizza le decisioni emerse nella
> sessione di grilling sulle Analitiche Personali del mobile. Si appoggia alle
> ADR esistenti del Diario della Mobilita e introduce la ADR 0030
> (aggregazione delle Analitiche Personali lato backend) e i nuovi termini di
> glossario: Analitiche Personali, Categoria di Mobilita, Finestra Analitica,
> Mappa di Frequentazione, Percorso Frequente.

## Problem Statement

La traccia del progetto richiede delle analitiche personali per l'utente
mobile: grafici giornalieri o settimanali sul tempo trascorso in movimento,
fermo, in bici, in auto e a piedi; una heatmap dei luoghi piu' frequentati; e
statistiche sui percorsi piu' frequenti, sulle distanze percorse e sulle
modalita' di mobilita' prevalenti.

Oggi l'app mostra solo le `Statistiche del Viaggio` di un singolo Viaggio
(nel Dettaglio Viaggio) e l'elenco dei Viaggi nel drawer. Manca del tutto una
vista che aggreghi la mobilita' del Proprietario del Viaggio **attraverso piu'
Viaggi**, sia come andamento recente sia come abitudini di lungo periodo. I dati
necessari esistono gia' (Segmenti di Mobilita con Etichetta di Attivita' e
durate, distanze dei Viaggi, Luoghi Significativi con conteggio visite), ma non
sono mai stati composti in una lettura d'insieme per l'utente.

## Solution

Introdurre le **Analitiche Personali**: una nuova schermata mobile, raggiungibile
da un'icona nell'AppBar della Home, che presenta in un'unica pagina scrollabile
tre sezioni, con lo stile flat gia' in uso (pannelli su `ColorPalette` /
`Dimensions`):

1. **Andamento recente** (guidato da una `Finestra Analitica` con toggle
   Giorno/Settimana): un grafico a barre impilate del tempo per `Categoria di
   Mobilita` (Fermo, A piedi, Corsa, In bici, In auto) e una card con le distanze
   della finestra (totale + breakdown per modalita').
2. **Mappa di Frequentazione** (cumulativa): una heatmap dei Luoghi Significativi
   pesati per frequenza di visita.
3. **Abitudini di sempre** (cumulative): la modalita' di mobilita' prevalente e i
   `Percorsi Frequenti` (coppie Origine -> Destinazione tra Luoghi Significativi).

L'aggregazione e' calcolata lato backend da un nuovo endpoint mobile
user-scoped che attraversa tutti i Viaggi e i Segmenti di Mobilita
dell'utente (ADR 0030), restituendo in una sola risposta sia i bucket
finestrati sia gli aggregati cumulativi. L'app si limita a mappare la risposta in
un modello di presentazione e a disegnarla.

## User Stories

1. As a Proprietario del Viaggio, I want to open a personal analytics screen
   from the Home, so that I can see my mobility at a glance without opening trips
   one by one.
2. As a Proprietario del Viaggio, I want a single scrollable screen that groups
   recent trends and lifetime habits, so that I do not have to navigate between
   many pages.
3. As a Proprietario del Viaggio, I want a stacked bar chart of time spent per
   Categoria di Mobilita, so that I can compare how much I move versus stay still.
4. As a Proprietario del Viaggio, I want the chart split into Fermo, A piedi,
   Corsa, In bici and In auto, so that I can see each travel mode separately.
5. As a Proprietario del Viaggio, I want a derived "In movimento" total, so that I
   can read my overall active time as the sum of the non-Fermo categories.
6. As a Proprietario del Viaggio, I want a Giorno/Settimana toggle, so that I can
   switch between the last 7 days (daily bars) and the last 8 weeks (weekly bars).
7. As a Proprietario del Viaggio, I want each bar labelled with its day or week,
   so that I can tell which period it represents.
8. As a Proprietario del Viaggio, I want to tap or read a legend of category
   colours, so that I can interpret the stacked segments.
9. As a Proprietario del Viaggio, I want time buckets computed in my device's
   local timezone, so that "today" matches my actual day.
10. As a Proprietario del Viaggio, I want the distances card to follow the same
    Finestra Analitica as the chart, so that the numbers match what I see above.
11. As a Proprietario del Viaggio, I want a total distance for the selected
    window, so that I know how far I travelled recently.
12. As a Proprietario del Viaggio, I want the window distance broken down per
    Categoria di Mobilita, so that I can see how far I went by foot, bike or car.
13. As a Proprietario del Viaggio, I want distances shown in readable units
    (km/m), so that the values are easy to understand.
14. As a Proprietario del Viaggio, I want a Mappa di Frequentazione heatmap of my
    most visited Luoghi Significativi, so that I can see where I spend most time.
15. As a Proprietario del Viaggio, I want the heatmap intensity weighted by how
    often I visit each place, so that frequent places stand out.
16. As a Proprietario del Viaggio, I want the heatmap to use my precise personal
    data, so that it reflects my real locations on my own device.
17. As a Proprietario del Viaggio, I want the heatmap to stay cumulative over all
    my history, so that it is meaningful even in weeks with few trips.
18. As a Proprietario del Viaggio, I want to see my prevalent mobility mode, so
    that I understand my dominant way of getting around.
19. As a Proprietario del Viaggio, I want the prevalent mode computed over all my
    history by total time, so that it reflects a stable habit rather than a single
    week.
20. As a Proprietario del Viaggio, I want a list of my Percorsi Frequenti as
    Origine -> Destinazione pairs between Luoghi Significativi, so that I can see
    my recurring journeys like "Casa -> Universita".
21. As a Proprietario del Viaggio, I want each Percorso Frequente to show how many
    Viaggi followed it, so that I can tell which routes are most common.
22. As a Proprietario del Viaggio, I want the Percorsi Frequenti ordered by
    frequency, so that my most common journeys are on top.
23. As a Proprietario del Viaggio, I want the endpoint loaded when I open the
    screen, so that I see data without extra taps.
24. As a Proprietario del Viaggio, I want pull-to-refresh, so that I can recompute
    my analytics after new trips sync.
25. As a Proprietario del Viaggio, I want a clear loading state, so that I know the
    analytics are being computed.
26. As a Proprietario del Viaggio, I want a clear error state with a retry action,
    so that I can recover from a failed load.
27. As a Proprietario del Viaggio with no synced Viaggi, I want an informative
    empty state, so that I understand I need to record trips first.
28. As a Proprietario del Viaggio with no confirmed Luoghi Significativi yet, I
    want the heatmap section to show its own empty state, so that an empty map does
    not look broken.
29. As a Proprietario del Viaggio with no matchable journeys, I want the Percorsi
    Frequenti section to explain why it is empty, so that I know more trips between
    known places are needed.
30. As a Proprietario del Viaggio, I want the analytics screen to match the rest
    of the app's flat visual style, so that it feels native to the product.
31. As a Proprietario del Viaggio, I want my analytics to be private to me, so that
    only my authenticated session can read them.

## Implementation Decisions

- **Backend aggregation, single mobile endpoint (ADR 0030).** A new user-scoped
  endpoint under the mobility router (mobile bearer auth) returns the full
  Analitiche Personali payload in one response. It accepts a `granularity`
  parameter (`day` | `week`) and the device's local timezone (IANA name or UTC
  offset) used for day/week bucketing. It returns **both** the windowed buckets
  and the cumulative aggregates.
- **Finestra Analitica.** `day` = last 7 days as 7 daily buckets; `week` = last 8
  weeks as 8 weekly buckets. The window scopes only the time-by-category trend and
  its distances. The Mappa di Frequentazione, Percorsi Frequenti and prevalent
  mode are cumulative over all history regardless of the toggle.
- **Categoria di Mobilita.** Time is bucketed one-to-one from the Etichetta di
  Attivita of each Segmento di Mobilita: IDLE -> Fermo, WALKING -> A piedi,
  RUNNING -> Corsa, BIKING -> In bici, MOVING_VEHICLE -> In auto. "In movimento"
  is never a stored bucket; it is the derived sum of the non-Fermo categories.
- **Bucket assignment.** A segment's whole duration is attributed to the local day
  of its `start_timestamp`; no splitting across midnight in v1. Daily buckets roll
  up into weekly buckets in the same local timezone.
- **Distances.** Per-bucket and window-total distances come from the movement
  Segmenti di Mobilita distances, also broken down per Categoria di Mobilita.
- **Prevalent mode.** The Categoria di Mobilita with the greatest total time over
  all history (Fermo excluded from "prevalent travel mode").
- **Percorso Frequente.** For each Viaggio, the start and end of its trajectory are
  matched to the nearest Luogo Significativo within that place's `radius_meters`
  (fallback threshold 150 m). A Percorso Frequente is the ordered (origin place ->
  destination place) pair; its frequency is the count of Viaggi matching that pair.
  Viaggi that do not match a Luogo Significativo at both ends are excluded. The
  endpoint returns the top pairs by frequency with their human-readable place
  labels.
- **Mappa di Frequentazione weights.** The endpoint returns the user's Luoghi
  Significativi with coordinates and a visit-frequency weight (from visit count /
  distinct days). The mobile heatmap renders these as a weighted Mapbox heatmap
  layer, reusing the existing Mapbox integration.
- **Mobile surface.** A new route (reached from an AppBar action on the Home)
  hosts a scrollable page composed of: a Giorno/Settimana segmented toggle, a
  stacked bar chart, a windowed distances card, a heatmap map panel, a prevalent
  mode tile, and a Percorsi Frequenti list. A cubit loads the endpoint on open and
  on pull-to-refresh and exposes loading/ready/empty/error states. A pure presenter
  maps the response DTO into the chart series, formatted distances, prevalent-mode
  label, route labels and per-section empty-state flags.
- **Charting dependency.** Add `fl_chart` to the mobile app for the stacked bar
  chart, themed to the flat `ColorPalette` so it matches the rest of the UI.
- **DTO / contract.** A new analytics DTO mirrors the endpoint schema: windowed
  buckets (period label + per-category seconds + per-category distance), cumulative
  prevalent mode, cumulative Percorsi Frequenti (origin label, destination label,
  count), and heatmap points (lat, lon, weight).

## Testing Decisions

- **What makes a good test here:** assert external, observable behaviour — the JSON
  the endpoint returns for a seeded history, and the display model the presenter
  produces for a given DTO — never internal helper shapes or private aggregation
  steps.
- **Backend (primary seam):** one HTTP-endpoint test suite hitting
  `GET /mobility/analytics` via the Django test `Client()` with mobile bearer auth.
  Seed Viaggi, Segmenti di Mobilita (with varied Etichette di Attivita and
  timestamps), distances, and Luoghi Significativi, then assert on the response:
  correct day/week buckets per Categoria di Mobilita, windowed distance totals and
  breakdown, cumulative prevalent mode, cumulative Percorsi Frequenti counts and
  labels, heatmap weights, local-timezone bucketing, user scoping (no cross-user
  leakage), and the empty-data response. Prior art: `test_privacy_export.py`,
  `test_trips_list.py`.
- **Mobile (primary seam):** a pure presenter test that maps representative
  analytics DTOs into the display model — chart series per Categoria di Mobilita,
  formatted distances, prevalent-mode label, route labels, and the per-section
  empty-state flags. Prior art: `trip_diary_presenter_test.dart`.
- **Mobile (secondary seam):** a cubit test for load / refresh / error / empty
  transitions against a fake analytics service. Prior art:
  `trips_list_cubit_test.dart`, `place_detail_cubit_test.dart`.
- The chart and heatmap **widgets** are intentionally thin over the tested display
  model and are not unit-tested beyond the app mounting without framework errors.

## Out of Scope

- Geometric trajectory clustering for routes (Percorsi Frequenti are O->D pairs
  between Luoghi Significativi, not path-shape clusters).
- Arbitrary date-range pickers; only the fixed Giorno (7 days) / Settimana
  (8 weeks) Finestra Analitica is supported in v1.
- Splitting a segment's duration across midnight or across week boundaries.
- Web Platform (Piattaforma Web) analytics; this PRD covers the mobile app only.
- Exporting or sharing the Analitiche Personali, and any privacy-aware
  (reduced-precision) variant of them — they are owner-only, precise, on-device.
- Per-Viaggio statistics, which remain the existing Statistiche del Viaggio.

## Further Notes

- The new glossary terms and ADR 0030 were captured during the grilling session;
  the endpoint contract should follow that glossary vocabulary.
- RUNNING segments may be rare in practice (the HAR fallback often yields WALKING),
  but Corsa remains a first-class Categoria di Mobilita so no data is silently
  folded away.
- Reuse the existing mobile service/cubit/DTO conventions (e.g. the trips and
  privacy-export features) for the new analytics service rather than introducing a
  new networking pattern.
