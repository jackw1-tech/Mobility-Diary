# PRD: Advanced Significant Place Recognition

Status: ready-for-agent

> Copia locale per il tracker. Questa PRD sintetizza le decisioni emerse nel
> brainstorming su Riconoscimento avanzato di luoghi significativi e si appoggia
> alle ADR esistenti del Diario della Mobilita e alle ADR 0020-0029 nate durante
> la definizione della feature.

## Problem Statement

La traccia del progetto richiede un riconoscimento avanzato di luoghi
significativi: clustering dei punti GPS per individuare aree frequentemente
visitate o soste ricorrenti, classificazione dei luoghi in categorie come casa,
universita, lavoro, palestra o altro anche mediante etichette manuali, e
associazione dei luoghi ai segmenti del diario per produrre descrizioni piu'
leggibili.

Oggi il progetto ha gia' il Diario della Mobilita, i Segmenti di Mobilita e una
logica locale di `SignificantPlace` per il singolo Viaggio, ma manca il
riconoscimento user-scoped di luoghi abituali attraverso piu' Viaggi. Manca
anche una review manuale nell'app che permetta all'utente di confermare,
rifiutare o etichettare i luoghi individuati automaticamente.

Il problema da risolvere e' quindi trasformare i `GpsPoint` grezzi in una
conoscenza duratura dei luoghi abituali del Proprietario del Viaggio, senza
alterare la segmentazione del diario gia' prodotta dalla pipeline HAR e senza
confondere soste singole con luoghi ricorrenti.

## Solution

Implementare un flusso user-scoped di `Riconoscimento dei Luoghi Significativi`
che usa solo i `GpsPoint` grezzi come sorgente di scoperta. Dopo
l'arricchimento asincrono finale di un Viaggio, il backend ricalcola i luoghi
significativi su tutta la storia dell'utente.

Il flusso e':

1. filtrare i `GpsPoint` con accuratezza troppo scarsa;
2. applicare una `stay detection` semplice `distance + time threshold` con
   centroide aggiornato, minimo 3 punti validi, permanenza minima di 5 minuti,
   tolleranza su piccoli gap temporali e raggio iniziale di circa 75 metri;
3. trasformare ogni permanenza trovata in una `Visita Candidata`;
4. applicare `DBSCAN` alle visite candidate dello stesso utente per raggruppare
   visite spazialmente compatibili nello stesso `Luogo Candidato`;
5. promuovere automaticamente un `Luogo Candidato` a `Luogo Significativo
   Confermato` quando ha evidenza su almeno 3 giorni distinti;
6. permettere review manuale nell'app mobile, con conferma, rifiuto o
   etichettatura del luogo tramite categoria chiusa e nome opzionale;
7. usare i luoghi confermati come read-time overlay sul Diario della Mobilita,
   arricchendo solo i segmenti `STOP` senza modificare la segmentazione
   persistita.

Il diario resta segment-based e continua a dipendere dalla pipeline asincrona
attuale per la struttura dei `MobilitySegment`. La nuova feature aggiunge
semantica dei luoghi sopra i segmenti esistenti, invece di riscriverli.

## User Stories

1. As a Proprietario del Viaggio, I want the system to mine recurring places from my GPS history, so that the diary can recognize places I visit often.
2. As a Proprietario del Viaggio, I want a single 5-minute permanence to be detected as one visit, so that the system can start learning from my behavior immediately.
3. As a Proprietario del Viaggio, I want recurrent permanences in the same area across different days to be merged into one place hypothesis, so that repeated visits do not stay fragmented.
4. As a Proprietario del Viaggio, I want a place to become automatically confirmed after 3 distinct days of evidence, so that useful places appear without manual work.
5. As a Proprietario del Viaggio, I want automatically confirmed places to enrich the diary even before I label them, so that the feature provides immediate value.
6. As a Proprietario del Viaggio, I want unlabeled confirmed places to appear with neutral text like `luogo abituale`, so that the diary becomes clearer without inventing semantics.
7. As a Proprietario del Viaggio, I want to review a list of Luoghi Candidati, so that I can decide which places are truly meaningful.
8. As a Proprietario del Viaggio, I want to review a list of Luoghi Significativi Confermati, so that I can refine or rename the places the system already trusts.
9. As a Proprietario del Viaggio, I want each candidate place to open on a map with its supporting GPS evidence, so that I can judge whether the system clustered the right area.
10. As a Proprietario del Viaggio, I want to confirm a candidate place manually, so that important places can become active even before enough automatic history accumulates.
11. As a Proprietario del Viaggio, I want to reject a candidate place manually, so that false positives stop bothering me.
12. As a Proprietario del Viaggio, I want rejected places to stay frozen until I manually reactivate them, so that the system does not keep proposing the same mistake.
13. As a Proprietario del Viaggio, I want to manually reactivate a rejected place, so that I can recover from an earlier wrong decision.
14. As a Proprietario del Viaggio, I want to assign a category like casa, universita, lavoro, palestra or altro, so that the place has a clear semantic meaning.
15. As a Proprietario del Viaggio, I want to add an optional custom name like `Bicocca`, so that the diary can use language that is meaningful to me.
16. As a Proprietario del Viaggio, I want my manual category and name to override automatic wording, so that my knowledge is stronger than the algorithm.
17. As a Proprietario del Viaggio, I want previously entered labels to survive future place recomputation, so that I do not lose work when the system updates its clusters.
18. As a Proprietario del Viaggio, I want newly processed trips to update my place history automatically, so that the places screen stays current without manual refresh workflows.
19. As a Proprietario del Viaggio, I want the system to recompute places from my full history after each processed trip, so that old and new evidence are clustered consistently.
20. As a Proprietario del Viaggio, I want my places to remain private to my own account, so that no place recognition is shared across users.
21. As a Proprietario del Viaggio, I want the diary to use place labels only for stops, so that movement descriptions remain honest and not over-interpreted.
22. As a Proprietario del Viaggio, I want the diary to say `sosta all'universita` or `sosta a Bicocca` when a stop matches a confirmed place, so that the timeline is easier to read.
23. As a Proprietario del Viaggio, I want movement segments to keep using activity labels and times, so that place recognition does not distort the travel narrative.
24. As a Proprietario del Viaggio, I want small GPS inaccuracies not to create fake places, so that the recognized places stay trustworthy.
25. As a Proprietario del Viaggio, I want very inaccurate GPS points ignored by the permanence detector, so that location noise does not masquerade as a stop.
26. As a Proprietario del Viaggio, I want the permanence detector to tolerate small sampling gaps, so that a real stop is not lost because of a brief telemetry interruption.
27. As a Proprietario del Viaggio, I want the permanence detector to require at least 3 valid points, so that two isolated fixes are not mistaken for a meaningful visit.
28. As a Proprietario del Viaggio, I want the permanence detector to use the centroid of the stop area, so that a stop remains stable even when the GPS jitters slightly.
29. As a Proprietario del Viaggio, I want recurring pass-through points like traffic lights or repeated routes not to become significant places, so that only real permanences matter.
30. As a Proprietario del Viaggio, I want place recognition to come from raw GPS permanence detection, so that the feature is grounded in my actual spatial behavior rather than only diary-derived stop artifacts.
31. As a Proprietario del Viaggio, I want one confirmed place to keep absorbing future nearby visits automatically, so that I do not have to reconfirm the same place every week.
32. As a Proprietario del Viaggio, I want the closest confirmed place to win when multiple places are nearby, so that the diary chooses one clear label.
33. As a Proprietario del Viaggio, I want manually labeled places to win ties over unlabeled automatic ones, so that my curation has priority.
34. As a Proprietario del Viaggio, I want the places screen to distinguish candidates, confirmed places and rejected places, so that the state of each place is obvious.
35. As a Proprietario del Viaggio, I want confirmed but unlabeled places still visible in the places screen, so that I can improve them later.
36. As a Proprietario del Viaggio, I want candidate places to show why they were proposed, such as visit count and days seen, so that I can trust or reject them with context.
37. As a Proprietario del Viaggio, I want a place label change to be reflected immediately when I reopen the diary, so that the diary feels live.
38. As a Proprietario del Viaggio, I want old diary stops to show the latest confirmed place names without rewriting trip structure, so that the diary remains coherent over time.
39. As a Proprietario del Viaggio, I want the app to remain usable even if no significant places are found yet, so that the feature does not degrade the diary for new users.
40. As a Proprietario del Viaggio, I want rare one-off stops to stay as visits but not become habitual places, so that the place list is not polluted.
41. As a Proprietario del Viaggio, I want manual confirmation to promote a place even before 3 distinct days, so that I can teach the system faster.
42. As a Proprietario del Viaggio, I want the feature to continue working as new trips arrive, so that place recognition improves over time.
43. As a developer, I want one clear discovery source for significant places, so that the algorithm is easier to reason about and evolve.
44. As a developer, I want raw GPS permanence detection separated from place clustering, so that visit extraction and place aggregation can be debugged independently.
45. As a developer, I want DBSCAN to group candidate visits rather than raw GPS points, so that place discovery operates on meaningful permanence episodes.
46. As a developer, I want trip-scoped `SignificantPlace` derivation removed from the diary pipeline, so that place semantics do not live in two conflicting systems.
47. As a developer, I want the existing asynchronous diary pipeline to remain the source of `MobilitySegment` structure, so that significant-place recognition does not destabilize HAR segmentation.
48. As a developer, I want significant-place mining to run after final HAR enrichment, so that it uses the latest synchronized trip history.
49. As a developer, I want place mining recomputation serialized per user, so that concurrent trip completions do not corrupt clusters or review state.
50. As a developer, I want read-time overlay instead of historical segment rewriting, so that place labels update immediately without expensive diary backfills.
51. As a developer, I want the overlay to match confirmed places to stops by spatial proximity, so that stop descriptions can be enriched without changing persistence shape.
52. As a developer, I want manual labels, confirmations and rejections to survive full history recomputation, so that human review remains the strongest signal.
53. As a developer, I want the API surface to expose both place-review data and diary-enriched read models, so that mobile and dashboard clients can build consistent UIs.
54. As a developer, I want candidate-place logic to stay user-scoped, so that privacy and ownership remain simple.
55. As a developer, I want tests to focus on external behavior of the detector, clustering, review state and diary overlay, so that refactors remain safe.
56. As a course evaluator, I want the feature to clearly demonstrate clustering of GPS points, manual labeling and readable diary association, so that the implementation maps cleanly to the assignment text.

## Implementation Decisions

- The feature is user-scoped. Significant-place discovery, confirmation,
  rejection, labels and diary overlays belong to one Proprietario del Viaggio
  at a time and are never shared across users.
- Significant-place discovery uses only raw `GpsPoint` evidence. The existing
  trip-scoped `SignificantPlace` derivation is removed from the diary pipeline
  and is no longer a discovery source.
- The asynchronous flow remains anchored to the existing diary enrichment
  lifecycle: after the final HAR enrichment of a Viaggio, a final significant
  place-mining step runs.
- The first implementation recomputes significant places against the full
  history of the user after each final trip enrichment rather than performing
  incremental cluster updates.
- Only one significant-place mining job may run at a time per user.
- Discovery is split into two algorithmic phases:
  `stay detection` over raw GPS to create `Visite Candidate`, then `DBSCAN`
  over visits to create `Luoghi Candidati`.
- `Stay detection` is a simple distance-plus-time threshold algorithm. The
  first implementation uses approximately 75 meters spatial tolerance, 5
  minutes minimum permanence, at least 3 valid GPS points, a centroid-based
  reference for the permanence area, and tolerance for small telemetry gaps up
  to a configured maximum.
- GPS points with poor accuracy are ignored before permanence detection.
- A `Visita Candidata` represents one permanence episode in time. A `Luogo
  Candidato` represents the aggregation of multiple compatible visits.
- `DBSCAN` is the first clustering algorithm. It clusters visits, not raw GPS
  points.
- A `Luogo Candidato` becomes automatically confirmed after evidence across at
  least 3 distinct days. No additional total-duration threshold is required in
  v1.
- Manual confirmation may also promote a place before it reaches the automatic
  3-day threshold.
- Rejected places are permanently frozen for automatic reconsideration until
  the user explicitly reactivates them.
- The mobile experience includes a dedicated places-review surface with at
  least three states: candidate, confirmed and rejected.
- The place-review UI opens each place on a map together with the supporting
  evidence used to propose it.
- Manual labeling is structured as a closed category plus an optional free-form
  name. The category set is `casa`, `universita`, `lavoro`, `palestra`,
  `altro`. A name like `Bicocca` can further refine the place.
- Manual labels, confirmations and rejections are stronger than clustering
  output and must survive full recomputation.
- Confirmed places automatically absorb future nearby visits without requiring
  the user to reconfirm them.
- Automatically confirmed places may enrich the diary before manual labeling.
  If no manual label exists yet, the diary uses neutral wording such as `luogo
  abituale`.
- The diary applies place semantics as a read-time overlay. Persisted
  `MobilitySegment` rows are not rewritten when place state changes.
- The overlay enriches only `STOP` segments, not `MOVE` segments.
- Stop-to-place matching is proximity-based. When multiple places match, the
  closest one wins; if the outcome is ambiguous, a manually labeled place wins
  over a purely automatic one.
- The new feature does not create, split or correct `MobilitySegment` rows.
  Segment structure remains the responsibility of the existing diary pipeline.
- Existing trip ingestion, HAR inference and segment generation remain in
  place. The new feature adds a user-scoped place-mining stage and a read-time
  labeling overlay on top of them.
- The implementation should introduce one high-level seam for place-mining
  orchestration and read-model enrichment, with the detector and clustering
  components kept behind that seam as replaceable internals.

## Testing Decisions

- Good tests verify external behavior, visible contracts and state transitions,
  not helper names or private implementation details.
- Prefer the highest seam possible: backend behavior tests around final
  diary-enrichment orchestration, place-review APIs and diary read-model
  overlay should carry most of the confidence.
- A narrow pure-algorithm seam is still justified for the permanence detector
  and clustering rules, because this is the mathematically sensitive part of
  the feature and is easiest to verify with deterministic inputs.
- Test the permanence detector with realistic GPS series to prove:
  permanence is found after 5 minutes and 3 valid points, poor-accuracy points
  are skipped, centroid-based radius handling works, and small gaps are
  tolerated only within the configured limit.
- Test that repeated pass-through points do not become `Visite Candidate`.
- Test that separate permanence episodes in the same area become separate
  visits before clustering.
- Test `DBSCAN` behavior at the visit level: compatible visits merge into one
  `Luogo Candidato`, unrelated visits stay separate, and a place auto-confirms
  only after 3 distinct days.
- Test per-user recomputation behavior: a new processed trip causes a full
  user-history recomputation, but manual labels, confirmations and rejections
  are preserved.
- Test per-user serialization behavior so concurrent trip completions cannot
  produce conflicting cluster state.
- Test place-review APIs for candidate listing, confirmed listing, rejected
  listing, map evidence payload, confirm, reject, reactivate and manual
  labeling.
- Test diary read-model overlay behavior: confirmed places enrich only `STOP`
  segments, unlabeled confirmed places use neutral wording, labeled places use
  category and optional name, and `MOVE` segments remain untouched.
- Test disambiguation rules when multiple confirmed places are nearby.
- Test that rejected places disappear from automatic candidate resurfacing
  until explicit reactivation.
- Prior art for backend behavior tests includes existing trip diary and trip
  track read-model tests, HAR final ingestion orchestration tests, and privacy
  read-model tests.
- Prior art for mobile/client behavior tests includes trip detail and privacy
  settings state tests already present in the repo.

## Out of Scope

- Cross-user clustering, shared places or any attempt to merge place knowledge
  across multiple users.
- Rewriting the diary segmentation or changing HAR movement/stop boundaries
  based on place recognition output.
- Applying place semantics to `MOVE` segments such as `verso casa` or
  `da universita a casa`.
- Automatic semantic inference of categories like `casa` or `lavoro` from time
  patterns. In v1 the meaningful category is provided manually by the user.
- Using trip-scoped `SignificantPlace` rows as a second discovery pipeline.
- Incremental cluster maintenance from only the latest trip.
- Reopening rejected places automatically after new evidence.
- Sharing, exporting or dashboard views dedicated specifically to the places
  review feature beyond the diary overlay and mobile review surface.
- Global POI lookup, reverse geocoding, external map-place providers or
  third-party semantic enrichment.
- A machine-learning classifier for place categories.
- Advanced adaptive clustering algorithms beyond the initial DBSCAN choice.

## Further Notes

- The feature deliberately separates `Visita Candidata` from `Luogo Candidato`.
  A single 5-minute permanence creates one visit; only multiple visits in the
  same area across distinct days create a habitual-place hypothesis.
- The removal of the current trip-scoped `SignificantPlace` discovery is a
  meaningful product simplification: place semantics now come from one user
  history algorithm instead of two competing notions of place.
- The read-time overlay keeps the diary feeling live: new manual labels appear
  immediately without mutating old segment persistence.
- The most important product surface in v1 is the mobile review flow, because
  it turns raw clustering output into user-trusted place semantics.
