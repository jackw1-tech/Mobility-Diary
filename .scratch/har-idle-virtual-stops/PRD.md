# PRD: HAR Idle Virtual Stops and Unified Diary Projection

Status: ready-for-agent

> Copia locale per il tracker. Questa PRD sintetizza la decisione di
> semplificare la gestione di `HAR IDLE` nel Diario della Mobilita senza
> falsare `StateTransition` o `MobilitySegment`, e si appoggia alle ADR che
> gia' separano segmentazione persistita e overlay read-time.

## Problem Statement

Oggi il Diario della Mobilita puo' mostrare una semantica confusa quando la
classificazione HAR produce run consecutivi di `IDLE` dentro intervalli che la
segmentazione principale considera movimento. Il risultato e' che il sistema
puo' finire con pezzi che, dal punto di vista dell'utente, sembrano
`MOVE + sto fermo`, oppure con frammentazioni diverse tra backend, mobile e web.

Dal punto di vista dell'utente il problema e' semplice: il diario deve essere
leggibile. Se mi sto muovendo voglio vedere un movimento con un'attivita'
coerente; se mi fermo abbastanza a lungo voglio vedere una sosta. Non voglio
che il sistema inventi falsi cambi di stato, ma non voglio nemmeno perdere
informazione utile sul tempo fermo rilevato dall'HAR.

Serve quindi una regola unica e piu' semplice che:

- elimini il concetto di segmento finale `MOVE/IDLE`;
- semplifichi la macchina a stati di acquisizione ai soli stati
  `movement` e `stationary`;
- mantenga onesti i dati persistiti;
- faccia comparire le soste rilevate dall'HAR nelle statistiche e nel diario
  mostrato;
- mantenga coerenti backend, mobile, web ed export.

## Solution

La soluzione introduce una distinzione netta tra:

- **acquisizione**, che usa una FSM semplificata con soli stati
  `movement` e `stationary`;
- **persistenza vera**, che continua a usare `StateTransition` e
  `MobilitySegment` come fonti strutturali del diario;
- **proiezione read-time**, che costruisce la vista mostrata all'utente e puo'
  aggiungere soste virtuali derivate dall'HAR.

Il flusso proposto e' il seguente:

1. la FSM di acquisizione viene ridotta ai soli stati `movement` e
   `stationary`; eventuali soglie, timer o contatori di conferma restano
   dettagli interni di debounce e non diventano piu' stati persistiti o
   semantici come `potentialMotion` o `activeTracking`;
2. dopo classificazione e correzione GPS delle label HAR, i run consecutivi di
   `IDLE` vengono raggruppati;
3. se un run `IDLE` dura meno di 2 minuti, in post-processing viene assorbito
   nell'attivita' precedente; se non esiste ancora un'attivita' precedente
   valida, viene assorbito nella prima attivita' successiva non-idle;
4. se un run `IDLE` dura almeno 2 minuti, non diventa un `MobilitySegment`
   persistito, ma genera un `Virtual Stop Interval` persistito come evidenza
   derivata separata;
5. la costruzione del diario mostrato unisce:
   `MOVE` persistiti, `STOP` persistiti e `Virtual Stop Interval`;
6. statistiche, export, mobile e web leggono la stessa proiezione del diario;
7. stop reali e stop virtuali consecutivi o sovrapposti vengono fusi in una
   sola sosta presentata all'utente.

In questo modello il database non finge cambi di stato mai avvenuti, ma la UI
mostra comunque una sosta quando l'HAR ha rilevato un fermo abbastanza lungo.

## User Stories

1. As a Proprietario del Viaggio, I want the diary to stop showing movement segments that are semantically idle, so that the timeline makes sense to me.
2. As a Proprietario del Viaggio, I want a short pause during movement to remain part of the previous activity, so that tiny stops do not fragment the diary.
3. As a Proprietario del Viaggio, I want a longer pause detected by HAR to appear as a stop in the diary, so that my timeline reflects real waiting or resting moments.
4. As a Proprietario del Viaggio, I want the threshold for an HAR-based stop to be 2 minutes, so that brief hesitation does not become a stop.
5. As a Proprietario del Viaggio, I want a pause shorter than 2 minutes to be absorbed into the previous activity, so that the diary stays simple.
6. As a Proprietario del Viaggio, I want stop time in statistics to include both real stops and HAR-detected virtual stops, so that the reported times match what I lived.
7. As a Proprietario del Viaggio, I want movement time in statistics to exclude long idle gaps, so that movement minutes are not inflated.
8. As a Proprietario del Viaggio, I want stop counts to merge adjacent stop evidence into one visible stop, so that repeated tiny cards do not clutter the diary.
9. As a Proprietario del Viaggio, I want the mobile diary detail and the web dashboard to tell the same story, so that the product feels trustworthy.
10. As a Proprietario del Viaggio, I want exported diaries to match what I saw in the app, so that sharing and reviewing a trip is coherent.
11. As a Proprietario del Viaggio, I want a long HAR idle gap between two movement segments to be shown as `Sosta rilevata`, so that the missing time is explained.
12. As a Proprietario del Viaggio, I want real persisted stops and HAR-derived stops to look consistent in the UI, so that the diary remains easy to read.
13. As a Proprietario del Viaggio, I want stop markers on the map to include HAR-derived stops too, so that the map view matches the diary.
14. As a Proprietario del Viaggio, I want the system not to invent fake `StateTransition` rows just to satisfy the UI, so that raw acquisition data remains honest.
15. As a Proprietario del Viaggio, I want the system not to persist fake `MobilitySegment` rows for every HAR idle gap, so that the structural diary model stays clean.
16. As a Proprietario del Viaggio, I want only the displayed view to become richer, so that place overlays and stop overlays can evolve without rewriting history.
17. As a developer, I want one explicit post-processing rule for consecutive HAR idle runs, so that the behavior is easy to reason about.
18. As a developer, I want short idle runs absorbed before building movement presentation, so that `MOVE/IDLE` disappears from the final visible model.
19. As a developer, I want long idle runs preserved as derived evidence separate from segments, so that I can explain where virtual stops come from.
20. As a developer, I want the read-time diary projection to be the single seam for combining real and virtual stops, so that backend, mobile and web stay aligned.
21. As a developer, I want the persistence model to distinguish raw facts from derived presentation artifacts, so that future refactors remain safe.
22. As a developer, I want a virtual stop interval to keep its own start and end timestamps, so that it can fill a real temporal gap precisely.
23. As a developer, I want the projection to merge overlapping or adjacent real and virtual stops, so that clients do not need their own custom merging logic.
24. As a developer, I want movement activity splits to be computed only from visible move intervals after idle absorption, so that activity statistics remain coherent.
25. As a developer, I want the same projection rules available to mobile, web and export builders, so that I do not debug three different diary semantics.
26. As a developer, I want tests to assert that no final visible segment can be `MOVE/IDLE`, so that the simplified rule is enforced permanently.
27. As a developer, I want the acquisition FSM to expose only `movement` and `stationary` as true states, so that trip-state semantics stay understandable.
28. As a developer, I want `potentialMotion`-style hysteresis to become an internal debounce mechanism rather than a persisted or domain-visible state, so that acquisition control stays simpler without becoming fragile.
29. As a Proprietario del Viaggio, I want state transitions synced from mobile to reflect only real movement versus stationary changes, so that backend trip structure is easier to explain.
30. As a course evaluator, I want the acquisition state model to be simple and defensible, so that the project architecture does not rely on confusing intermediate semantic states.
31. As a course evaluator, I want the diary semantics to be understandable and defensible, so that the implementation looks intentional rather than accidental.
32. As a course evaluator, I want the design to separate raw evidence, persisted structure and displayed overlay, so that the architecture is easier to explain.

## Implementation Decisions

- The conceptual model is split into three layers:
  raw evidence, persisted diary structure, and displayed diary projection.
- The acquisition FSM is simplified to two domain states only:
  `movement` and `stationary`.
- Existing intermediate concepts such as `potentialMotion` and
  `activeTracking` are no longer modeled as first-class states. If hysteresis,
  grace periods or motion confirmation counters remain necessary, they stay as
  internal transition evidence and not as synced or user-meaningful states.
- Synced `StateTransition` rows should therefore represent only changes between
  `movement` and `stationary`.
- Raw evidence remains the existing acquisition data:
  GPS, sensor windows, HAR predictions and `StateTransition`.
- Persisted diary structure remains centered on `MobilitySegment` and keeps only
  true structural `MOVE` and `STOP` rows.
- `MOVE/IDLE` is no longer considered an acceptable final displayed outcome.
- Consecutive HAR `IDLE` windows are grouped into `HAR Idle Runs` during
  post-processing after classification and GPS correction.
- If an `HAR Idle Run` lasts less than 2 minutes, its time is absorbed into the
  previous non-idle activity run. This is the normal rule.
- If an `HAR Idle Run` appears at the beginning of a movement span and there is
  no previous non-idle activity available, the implementation must absorb it
  into the first following non-idle activity run.
- If an `HAR Idle Run` lasts at least 2 minutes, it does not become a
  `MobilitySegment`. Instead it is materialized as a persisted
  `Virtual Stop Interval` tied to the trip as derived evidence.
- A `Virtual Stop Interval` is user-visible but structurally weaker than a real
  `STOP`: it exists to explain an HAR-detected stationary gap in the displayed
  diary, not to rewrite trip state history.
- The segmentation pipeline must stop turning long `HAR IDLE` runs into
  displayed `MOVE/IDLE` fragments.
- The highest seam for the feature is the backend diary projection/read-model
  builder. This builder becomes the source of truth for:
  visible diary segments, stop counts, stopped time, movement time and export
  semantics.
- The work of merging persisted real stops and HAR-derived virtual stops must
  happen in the backend projection layer, not in mobile or web presenters.
- The projection layer merges three temporal sources:
  persisted `MOVE`, persisted `STOP`, and persisted `Virtual Stop Interval`.
- The projection output still exposes only a simple user-facing timeline of
  `MOVE` and `STOP`.
- The projection should use explicit terminology:
  `Real Stop` = persisted `MobilitySegment(kind=STOP)`;
  `Virtual Stop` = persisted `Virtual Stop Interval`;
  `Visible Stop` = the stop entry returned by the backend read model after
  merging real and virtual stop evidence.
- The merge algorithm should be interval-based and deterministic:
  first collect all `Real Stop` and `Virtual Stop` intervals for the trip,
  sort them by `(start, end)`, then scan left-to-right and merge any two stop
  intervals that overlap, touch, or are within the configured stop-gap
  tolerance.
- The start of a `Visible Stop` is the minimum start among its merged stop
  intervals; the end is the maximum end among its merged stop intervals.
- `MOVE` intervals are never merged with stop intervals. A `Virtual Stop` may
  explain a temporal gap between two moves, but it must never widen or relabel
  a move entry itself.
- If a `Virtual Stop` sits entirely inside a `Real Stop`, the result is still
  one `Visible Stop` with the real stop's outer boundaries.
- If a `Real Stop` sits entirely inside a `Virtual Stop`, the result is one
  `Visible Stop` with the virtual stop's outer boundaries.
- If a `Virtual Stop` bridges two nearby `Real Stop` intervals, the result is
  one larger `Visible Stop` only when the intervals form a continuous
  stop-like block according to the same merge rule; otherwise they remain
  separate visible stops.
- Stop labels are assigned after temporal merging, not before. This avoids
  producing multiple visible stop cards that later collapse semantically.
- Label precedence for one `Visible Stop` should be:
  confirmed significant-place label if exactly one merged stop block maps
  cleanly to it; otherwise neutral stop wording such as `Sosta rilevata`.
- Statistics must be computed from the projected timeline, not directly from
  raw segments:
  `stopped time` = sum of `Visible Stop` durations;
  `movement time` = sum of visible `MOVE` durations;
  `stop count` = number of `Visible Stop` entries.
- When a virtual stop overlaps or touches a real stop, the projection merges
  them into a single visible stop.
- When multiple virtual-stop or real-stop intervals are adjacent within the
  configured merge tolerance, the projection emits one visible stop card.
- The UI wording for an HAR-derived visible stop remains neutral, such as
  `Sosta rilevata`, unless another overlay such as a confirmed significant
  place provides a richer label.
- The significant-place overlay remains read-time and can enrich both real and
  virtual visible stops without rewriting persisted structure.
- Mobile trip detail, web dashboard and privacy/export builders must consume
  the same backend-projected semantics rather than re-deriving idle handling
  or stop merging independently.
- Client-side presenters may still format and order data, but they should not
  invent their own definition of what counts as stop versus move.
- The feature introduces one new derived persistence concept, the
  `Virtual Stop Interval`, rather than overloading `StateTransition` or
  `MobilitySegment`.
- The implementation should preserve the current asynchronous final-enrichment
  architecture: HAR inference happens once at trip processing time, and read
  models are built from persisted outputs rather than rerunning the classifier
  on every request.
- Sampling behavior may still differentiate short-stationary versus
  long-stationary power modes internally, but those are sampling profiles, not
  additional domain states in the FSM.

## Testing Decisions

- Good tests assert externally visible diary semantics and statistics, not the
  names of helpers or the internal shape of loops.
- For the FSM simplification, good tests verify the externally observable
  transitions and acquisition outputs rather than the exact counters used for
  debounce.
- The primary seam to test is the read-model/projection layer, because that is
  where the user-visible meaning of stops and movements is decided.
- The highest seam for the acquisition simplification is the mobile acquisition
  domain plus synced transition behavior: given motion and GPS evidence, the
  system should emit only `movement` and `stationary` transitions.
- A secondary pure seam is justified for `HAR Idle Run` post-processing,
  because the less-than-2-minutes absorption rule is easy to test
  deterministically and easy to break accidentally.
- Test that acquisition no longer emits `potentialMotion` or `activeTracking`
  as first-class synced states.
- Test that movement confirmation and return-to-stationary logic still work
  after the two-state simplification.
- Test that consecutive `HAR IDLE` windows are grouped into one idle run.
- Test that an idle run shorter than 2 minutes is absorbed into the previous
  non-idle activity and does not create a visible stop.
- Test that a short idle run does not create a `Virtual Stop Interval`.
- Test that an idle run of at least 2 minutes produces a `Virtual Stop
  Interval`.
- Test that the projection emits no visible `MOVE/IDLE` outcome once the rule
  is applied.
- Test the projection merge algorithm with these concrete interval patterns:
  real-stop contains virtual-stop, virtual-stop contains real-stop, virtual-stop
  bridging two nearby real-stops, and isolated virtual-stop between two moves.
- Test that a long idle gap between two movement intervals becomes one visible
  stop in diary read models.
- Test that a real `STOP` adjacent to a virtual stop is merged into one visible
  stop with the correct total duration.
- Test that stop counts and stopped time include both real and virtual stops.
- Test that movement duration and activity split exclude long idle gaps and
  reflect short-idle absorption.
- Test that mobile diary detail, web dashboard and export consume equivalent
  projected semantics for the same trip.
- Test that significant-place labeling can still overlay onto a visible stop
  after the introduction of virtual stops.
- Prior art for backend behavior tests includes existing pipeline,
  trip-diary, privacy-export and dashboard read-model tests.
- Prior art for client behavior tests includes existing mobile presenter tests
  and dashboard utility tests that already validate visible segment collapse and
  statistics.

## Out of Scope

- Rewriting raw acquisition events to fabricate new `StateTransition` rows.
- Treating every HAR idle window as a persisted `MobilitySegment`.
- Re-running the HAR model at request time to rebuild stop evidence on demand.
- Inferring semantic place categories from virtual stops alone.
- Changing the significant-place mining algorithm beyond allowing it to overlay
  on top of visible stops.
- Introducing new public acquisition states beyond `movement` and `stationary`.
- Introducing live-trip incremental projection rules before final HAR
  enrichment completes.
- Using external map providers or POI databases to explain virtual stops.

## Further Notes

- This design intentionally treats HAR as an evidence source, not as the sole
  owner of trip structure.
- The simplification is product-facing:
  the user should see only movements and stops, not internal classifier
  ambiguity.
- The same simplification principle now also applies one layer earlier:
  acquisition may keep internal debounce evidence, but the domain FSM should
  expose only `movement` and `stationary`.
- The choice of a separate `Virtual Stop Interval` keeps the database honest
  while still preserving useful derived information.
- The most important architectural consequence is that stop semantics should be
  defined once in the backend projection and then consumed consistently
  everywhere else.
