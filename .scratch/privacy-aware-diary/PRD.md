# PRD: Privacy-Aware Mobility Diary

Status: ready-for-agent

> Copia locale per il tracker; la versione di brainstorming vive in
> `docs/prd/privacy-aware-diary.md`. Decisione architetturale di riferimento:
> ADR 0019, privacy-aware views generate backend-side.

## Problem Statement

La traccia 2 del progetto CAS 2026 chiede di trasformare il Diario della
Mobilita in un diario privacy-aware: l'utente deve poter scegliere un Livello
Privacy per esportazione o condivisione, il sistema deve produrre una versione
anonimizzata o perturbata del diario, e la Piattaforma Web deve confrontare la
traccia reale con quella privacy-aware mostrando il trade-off tra privacy e
qualita' del servizio.

Oggi il progetto ha gia' una Preferenza Privacy utente (`precise`,
`approximate`, `aggregated`), ma questa scelta non modifica ancora nessun dato
del diario. La Vista Privata del Diario, i Segmenti di Mobilita, le Etichette di
Attivita e i Luoghi Significativi continuano a essere serviti con geometria
precisa. Manca quindi il comportamento centrale richiesto dalla traccia:
generare una Vista Privacy-Aware concreta, confrontabile e esportabile.

La confusione principale da sciogliere e' questa: nel progetto il backend resta
trusted e conserva i dati precisi per HAR, segmentazione, luoghi significativi e
ispezione privata. La tecnica di privacy protegge la rappresentazione
pubblicata, condivisa o esportata del diario, non il backend dai dati originali.

## Solution

Implementare una Vista Privacy-Aware generata backend-side a partire dalla Vista
Privata del Diario. La tecnica scelta e' spatial cloaking con griglia metrica,
interpretabile anche come truncation-based spatial cloaking: ogni coordinata GPS
reale viene assegnata a una cella di griglia e la coordinata pubblicata diventa
il centro della cella.

Il mapping dei Livelli Privacy e':

- `precise`: nessun cloaking; la vista privacy-aware coincide con la geometria
  privata ed e' esplicitamente non protetta;
- `approximate`: celle metriche da 150 metri;
- `aggregated`: celle metriche da 400 metri.

La trasformazione si applica solo alla geometria di posizione: Traiettoria del
Viaggio, path dei Segmenti di Mobilita e centro dei Luoghi Significativi. Le
Etichette di Attivita, gli intervalli temporali e le statistiche di durata
restano quelli prodotti dalla pipeline HAR sui dati reali. In v1 non si
ricomputano previsioni HAR su dati perturbati.

La Piattaforma Web deve mostrare la Vista Privata del Diario e la Vista
Privacy-Aware nello stesso Dettaglio Viaggio, con layer mappa confrontabili,
metriche di Privacy Perturbation e Quality of Service, e possibilita' di
anteprima dei tre livelli. L'app mobile deve mantenere il diario normale come
vista privata, ma aggiungere un'azione "esporta diario" che usa la Vista
Privacy-Aware e produce un'anteprima testuale copiabile/condivisibile.

## User Stories

1. As a Proprietario del Viaggio, I want to choose a Livello Privacy for diary sharing, so that I can control how precise my shared mobility data is.
2. As a Proprietario del Viaggio, I want my normal mobile diary to remain precise, so that I can inspect my own movements without losing useful detail.
3. As a Proprietario del Viaggio, I want exports to respect my Preferenza Privacy, so that I do not accidentally share the precise GPS trace.
4. As a Proprietario del Viaggio, I want a text export preview before sharing, so that I can see what information will leave the private diary.
5. As a Proprietario del Viaggio, I want approximate exports to use 150 meter cloaking cells, so that the shared route is useful but not exact.
6. As a Proprietario del Viaggio, I want aggregated exports to use 400 meter cloaking cells, so that the shared route is coarser when I need more privacy.
7. As a Proprietario del Viaggio, I want precise exports to be clearly marked as unprotected, so that I understand the risk before sharing them.
8. As a Proprietario del Viaggio, I want significant stops in approximate and aggregated exports to use generic wording, so that labels like home, work, or university are not leaked.
9. As a Proprietario del Viaggio, I want exported coordinates to be labeled as approximated coordinates, so that nobody mistakes them for the original GPS points.
10. As a Proprietario del Viaggio, I want the same privacy setting to affect export and web comparison, so that the product behaves consistently.
11. As an Operatore Web, I want to see the private trace and the privacy-aware trace together, so that I can evaluate the effect of the privacy technique.
12. As an Operatore Web, I want a map layer toggle for private, privacy-aware, and both, so that I can inspect the comparison in the clearest mode.
13. As an Operatore Web, I want the dashboard to start from the owner's saved Preferenza Privacy, so that the view reflects the user's configured choice.
14. As an Operatore Web, I want to preview all supported Livelli Privacy in the dashboard, so that I can demonstrate the privacy-quality trade-off without editing the user's profile.
15. As an Operatore Web, I want approximate and aggregated traces to remain map-ready lines, so that I can still compare route shape and service quality.
16. As an Operatore Web, I want optional cloaking-cell polygons on the map, so that it is clear that a published coordinate represents a region.
17. As an Operatore Web, I want movement Segmenti di Mobilita to keep activity colors and labels while their paths are cloaked, so that the diary stays readable.
18. As an Operatore Web, I want Luoghi Significativi to be cloaked in the privacy-aware view, so that the most sensitive recurring places are protected.
19. As an Operatore Web, I want private labels to remain available only in the private comparison, so that privacy-aware labels do not leak sensitive semantics.
20. As an Operatore Web, I want Privacy Perturbation metrics, so that I can quantify how far published positions moved from real positions.
21. As an Operatore Web, I want Quality of Service metrics, so that I can quantify how much utility is lost when using a coarser privacy level.
22. As an Operatore Web, I want the dashboard to compare `precise`, `approximate`, and `aggregated`, so that the project requirement is visually demonstrable.
23. As a developer, I want the privacy-aware view generated on read, so that we do not persist a second copy of every perturbed trip.
24. As a developer, I want the cloaking transformation to be deterministic, so that tests, exports, metrics, and refreshes are stable.
25. As a developer, I want the grid to be metric and global, so that 150 m and 400 m mean the same thing outside Bologna or any demo area.
26. As a developer, I want the same cloaking service used for tracks, segments, and significant places, so that no precise geometry leaks through a secondary path.
27. As a developer, I want the HAR pipeline to continue using real sensor and GPS evidence, so that activity recognition quality is not damaged before diary creation.
28. As a developer, I want HAR labels not to be recomputed for the privacy-aware view in v1, so that the first privacy slice stays focused on location release.
29. As a developer, I want the web dashboard endpoint to return private and privacy-aware read models together, so that the frontend can render direct comparison without multiple inconsistent calls.
30. As a developer, I want mobile export to use a dedicated endpoint, so that the normal mobile diary remains a private detailed read model.
31. As a developer, I want the export endpoint to use the user's saved Preferenza Privacy, so that mobile export behavior is predictable.
32. As a developer, I want precise, approximate, and aggregated output to share one contract shape, so that frontend and mobile code do not branch around different schemas.
33. As a developer, I want consecutive duplicate cloaked cell centers to be collapsible for rendering, so that aggregated traces stay readable on a map.
34. As a developer, I want perturbation metrics computed on the original point set before display collapsing, so that the metric honestly measures privacy transformation.
35. As a developer, I want privacy metrics to be present even when the user selects `precise`, so that the zero-perturbation baseline is explicit.
36. As a course evaluator, I want the implementation to map clearly to spatial cloaking from the lecture slides, so that the privacy requirement is academically recognizable.

## Implementation Decisions

- Privacy-aware views are generated backend-side from stored private diary data.
  The backend remains trusted and stores precise evidence.
- The selected privacy technique is spatial cloaking via deterministic metric
  grid quantization.
- `approximate` uses 150 meter cells; `aggregated` uses 400 meter cells.
- The published point for a cloaked coordinate is the center of its metric cell.
- The grid is global and metric, not tied to Bologna and not implemented by
  naively dropping latitude/longitude decimal digits.
- The privacy-aware transformation affects only location geometry in v1:
  Traiettoria del Viaggio, Segmento di Mobilita path and Luogo Significativo
  center.
- Raw accelerometer, gyroscope and other HAR sensor windows are not transformed
  by this feature.
- HAR runs on real data. Segment intervals, Etichette di Attivita and
  activity-duration statistics are reused from the private diary.
- HAR predictions are not recomputed on perturbed or cloaked data in v1.
- For `approximate` and `aggregated`, privacy-aware significant-stop labels are
  generic and must not reveal private semantics such as home, work or
  university.
- The `precise` level is allowed but must be presented as unprotected wherever
  it is exported or used as a shareable view.
- Persist real evidence, real trip path, real Segmenti di Mobilita, real Luoghi
  Significativi, HAR labels and user Preferenza Privacy.
- Do not persist a second full copy of perturbed trips, perturbed GPS points,
  perturbed segments, or perturbed HAR predictions in v1.
- Extend the existing web Dettaglio Viaggio read model with a `privacy_aware`
  block containing selected level, cloaked track, cloaked diary segments and
  metrics.
- The web dashboard uses the owner's saved Preferenza Privacy as the initial
  privacy-aware level, but permits preview of all levels.
- The web dashboard renders a single comparison map with private and
  privacy-aware layers, plus a layer toggle.
- The web dashboard may render translucent cloaking cells when the privacy-aware
  layer is visible.
- Add a dedicated mobile privacy export endpoint. The normal mobile diary
  endpoint continues to return the Vista Privata del Diario.
- The mobile export endpoint returns a text-friendly privacy-aware
  representation controlled by the user's saved Preferenza Privacy.
- Mobile v1 export is text preview plus copy/simple share behavior. It does not
  include PDF generation, file generation or a mobile comparison map.
- Privacy Perturbation is the distance between each real position and its
  published cell-center position. Summaries should include at least mean and
  maximum distance.
- Quality of Service v1 is relative distance error:
  absolute difference between real route distance and privacy-aware route
  distance, divided by real route distance.
- Consecutive duplicate cloaked cell centers may be collapsed for map rendering,
  but perturbation metrics are computed before this display simplification.
- The same internal privacy transformation service should be reused by dashboard
  comparison and mobile export.

## Testing Decisions

- Prefer tests at the highest external seam: backend API responses for web trip
  dashboard comparison and mobile privacy export. These tests should validate
  the user-observable contract: level, cloaked geometry, masked labels and
  metrics.
- Add focused geometry tests for the metric grid cloaking service because this
  is the mathematically sensitive part of the feature. These tests should prove
  determinism, global applicability, 150 m/400 m behavior and valid coordinate
  output.
- Backend tests should assert that `approximate` and `aggregated` do not return
  precise coordinates for tracks, movement segment paths or significant-place
  centers.
- Backend tests should assert that `precise` returns zero Privacy Perturbation
  and no geometry change, while still being explicitly marked as unprotected in
  export-oriented output.
- Backend tests should assert that sensitive Luogo Significativo labels are
  masked in privacy-aware output for `approximate` and `aggregated`.
- Backend tests should assert that HAR activity labels and segment time
  intervals are preserved across private and privacy-aware views.
- Backend tests should assert that Quality of Service relative distance error is
  present and computed from private vs privacy-aware distance.
- Web dashboard tests should cover privacy level selection, layer toggles,
  presence of metric summaries and rendering of privacy-aware data without
  removing the private comparison.
- Mobile tests should cover the export action, export preview state, use of the
  dedicated privacy export endpoint and absence of private geometry in
  approximate or aggregated export text.
- Prior art for backend testing includes privacy settings API tests and web
  dashboard/read-model tests.
- Prior art for mobile testing includes privacy settings service/cubit/onboarding
  tests and trip detail state tests.
- Tests should verify external behavior and contract shape, not internal helper
  names or implementation details.

## Out of Scope

- Mobile-side perturbation before upload. That would be needed for an untrusted
  backend model, but this project slice assumes backend-side generation.
- Protecting raw sensor windows used by HAR.
- Recomputing HAR predictions on cloaked or perturbed data.
- Persisting a second privacy-aware copy of every trip, segment, point or HAR
  prediction.
- Differential privacy, dummy locations, peer-to-peer privacy, pseudonyms,
  k-anonymity and temporal aggregation as first implementation techniques.
- A zone-only aggregated visualization. `aggregated` remains a coarse
  privacy-aware trace made of 400 meter cell centers.
- PDF export, file export and rich mobile share sheets beyond simple text
  preview/copy/share.
- A mobile map comparison view for private vs privacy-aware traces.
- Per-trip privacy snapshots. The first implementation uses the current user
  Preferenza Privacy when generating privacy-aware views.
- User-configurable arbitrary cell sizes. v1 uses fixed 150 m and 400 m levels.
- A privacy guarantee against the backend itself.

## Further Notes

- This PRD follows ADR 0015, where privacy preference is a user-scoped setting,
  and ADR 0019, where privacy-aware views are generated backend-side.
- The feature is intentionally scoped to location privacy because the CAS brief
  and lecture techniques discussed here focus on position release.
- The dashboard comparison is the clearest project demonstration: private trace,
  cloaked trace, perturbation metric and quality loss visible together.
- The mobile export feature is still important because it makes the user's
  privacy choice practical rather than just a dashboard demo.
- In a future stronger privacy model, the mobile app could perturb before upload
  and the backend would never receive precise GPS. That is a different trust
  model and should be designed separately.
