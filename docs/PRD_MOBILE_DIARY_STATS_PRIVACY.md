# PRD - Mobile Dettaglio Viaggio, Statistiche, Preferenza Privacy e SSE

> Labels: ready-for-agent
> Versione 2 - 2026-06-23.
> Scope: app Flutter `mobile/diary`, backend Django/Ninja, Diario della
> Mobilita, Preferenza Privacy, Dettaglio Viaggio e stream eventi foreground.

## Problem Statement

La Proposta 2 richiede che l'app mobile non si limiti a raccogliere GPS e
sensori, ma mostri un Diario della Mobilita leggibile, statistiche personali e
una scelta privacy-aware. Oggi il sistema ha gia una pipeline forte: Core
Ingestion inline, Raw Sensor Ingestion, HAR finale asincrono, read model
segmentato e mappa. Manca pero una esperienza mobile unificata che renda visibile
il valore prodotto dalla pipeline.

Dal punto di vista dell'utente, dopo aver fermato un Viaggio il comportamento
desiderato e:

- vedere subito il Viaggio appena il Core e completato, senza aspettare HAR;
- aprire automaticamente il Dettaglio Viaggio;
- vedere la Traiettoria del Viaggio base mentre l'Arricchimento del Viaggio e in
  corso;
- ricevere l'aggiornamento appena HAR completa, senza polling continuo;
- consultare Mappa, Timeline del Viaggio e Statistiche del Viaggio in un unico
  posto;
- poter modificare la Preferenza Privacy globale dal profilo.

Serve anche rendere esplicito il contratto backend: se la Core Ingestion e
completata, il backend deve avere materializzato un `trip_id` e deve restituirlo
al mobile. Un `core_status=COMPLETED` con `trip_id=null` e uno stato ambiguo e
non utilizzabile dal nuovo flusso UI/SSE.

## Solution

Costruire una nuova esperienza mobile intorno al Dettaglio Viaggio.

Quando la Core Ingestion completa, la SyncQueue salva `remoteTripId`,
`coreStatus=COMPLETED` e `coreMapAvailable`. La UI osserva lo stato di
sincronizzazione e apre automaticamente il Dettaglio Viaggio una sola volta per
quel Viaggio. Il Dettaglio Viaggio contiene tre tab:

- Mappa;
- Diario;
- Statistiche.

La Mappa mostra subito la Traiettoria del Viaggio base se disponibile. Se il
Diario della Mobilita non e ancora arricchito, il Dettaglio Viaggio apre uno
stream SSE foreground per quel singolo Viaggio. Quando il backend emette
`diary_enriched`, il mobile ricarica il read model con `GET /diary` e aggiorna
Mappa, Timeline del Viaggio e Statistiche.

Le Statistiche del Viaggio sono calcolate lato mobile dai Segmenti di Mobilita.
Non diventano un nuovo dato persistito.

La Preferenza Privacy e una impostazione globale utente salvata nel backend in
un modello dedicato one-to-one. Per ora viene solo visualizzata e modificata nel
Profilo/Impostazioni: non viene ancora applicata a mappe, diario o export.

## User Stories

1. As a mobile user, I want the app to open my Viaggio as soon as Core Ingestion completes, so that I do not wait for HAR before seeing something useful.
2. As a mobile user, I want the Dettaglio Viaggio to open automatically after a successful sync, so that I do not need to hunt for the new trip in a list.
3. As a mobile user, I want the app to show the base Traiettoria del Viaggio while HAR is processing, so that I can immediately verify where I moved.
4. As a mobile user, I want the app to clearly show that diary analysis is still in progress, so that I understand why labels and statistics are not ready yet.
5. As a mobile user, I want the app to update when HAR completes, so that the final diary appears without manual refresh.
6. As a mobile user, I want that update to be event-driven while the app is open, so that the app does not keep polling aggressively.
7. As a mobile user, I want the app to refetch the diary after an event, so that I always see backend-confirmed diary data.
8. As a mobile user, I want to see a Mappa tab for one Viaggio, so that I can inspect the route visually.
9. As a mobile user, I want the Mappa tab to switch from base route to segmented route after enrichment, so that activity changes become visible.
10. As a mobile user, I want to see a Diario tab for one Viaggio, so that I can understand the trip as readable time intervals.
11. As a mobile user, I want the Diario tab to show movement segments and stop segments, so that I can distinguish travel from stays.
12. As a mobile user, I want each Segmento di Mobilita to show start time, end time and duration, so that I understand when it happened.
13. As a mobile user, I want each movement segment to show an Etichetta di Attivita, so that I can understand the mobility mode.
14. As a mobile user, I want movement segments to show distance when available, so that I can understand how far I travelled in that interval.
15. As a mobile user, I want stop segments to show Luoghi Significativi when available, so that stops are readable without raw coordinates.
16. As a mobile user, I want the Diario tab to avoid fake segments before HAR finishes, so that the app does not mislead me.
17. As a mobile user, I want to see a Statistiche tab for one Viaggio, so that I can summarize my mobility.
18. As a mobile user, I want to see total trip duration, so that I understand how long the Viaggio lasted.
19. As a mobile user, I want to see total distance, so that I understand how far I travelled.
20. As a mobile user, I want to see movement time and stopped time, so that I can compare active movement with stays.
21. As a mobile user, I want to see time by Etichetta di Attivita, so that I can compare walking, running, biking, vehicle and idle time.
22. As a mobile user, I want activity statistics shown with proportional bars, so that the distribution is easy to read.
23. As a mobile user, I want to see the number of stops or Luoghi Significativi, so that the diary communicates places as well as movement.
24. As a mobile user, I want pending statistics to be clearly unavailable before enrichment, so that I do not mistake partial data for final analytics.
25. As a mobile user, I want a Profilo/Impostazioni page, so that account and privacy settings have a natural home.
26. As a mobile user, I want to see my name and email in the profile, so that I know which account is active.
27. As a mobile user, I want to select a Livello Privacy, so that I can choose how precise future privacy-aware views should be.
28. As a mobile user, I want to choose between Precisa, Approssimata and Aggregata, so that the choice matches the project privacy language.
29. As a mobile user, I want privacy changes to be saved on the backend, so that the setting survives app restarts.
30. As a mobile user, I want the profile to show loading and saving states, so that I know whether my preference was saved.
31. As a mobile user, I want profile errors to be visible and retryable, so that network problems are recoverable.
32. As a mobile user, I want logout available from the profile, so that account actions are grouped sensibly.
33. As a frontend developer, I want one Dettaglio Viaggio state owner to feed map, diary and statistics, so that tabs stay consistent.
34. As a frontend developer, I want the SSE event to be a wake-up signal only, so that the backend read model remains the source of truth.
35. As a frontend developer, I want the stream lifecycle tied to the Dettaglio Viaggio page, so that connections close when no longer needed.
36. As a backend developer, I want `core_status=COMPLETED` to guarantee a `trip_id`, so that clients can rely on the Core response.
37. As a backend developer, I want an explicit error if Core is completed without a Trip, so that corrupt states are not hidden behind a null response.
38. As a backend developer, I want a dedicated privacy settings API, so that authentication endpoints do not become a general settings surface.
39. As a backend developer, I want a dedicated UserPrivacySettings model, so that privacy preferences can evolve separately from user identity.
40. As a project evaluator, I want the demo to show diary, statistics and privacy controls, so that the mobile app visibly satisfies Proposta 2.
41. As a project evaluator, I want the app to demonstrate event-driven update after HAR, so that the async backend pipeline is visible in the product.
42. As a project evaluator, I want the app to avoid pretending HAR is done before it is done, so that the demo is technically honest.

## Implementation Decisions

- The scope is a single Viaggio, not an entire day.
- The mobile experience is centered on Dettaglio Viaggio.
- Dettaglio Viaggio has three tabs: Mappa, Diario, Statistiche.
- The current map experience becomes the Mappa tab or is extracted into a reusable map tab component.
- The Diario tab presents a Timeline del Viaggio derived from Segmenti di Mobilita.
- The Timeline del Viaggio shows interval, duration, movement/stop kind, Etichetta di Attivita, movement distance and stop place information when available.
- The Statistiche tab calculates aggregate measures on the mobile from the loaded diary read model.
- Statistiche del Viaggio include duration, total distance, movement time, stopped time, time by Etichetta di Attivita, and count of stops or Luoghi Significativi.
- Statistics are rendered as numeric cards plus proportional activity bars.
- Statistics are not persisted as a backend model in this iteration.
- Before HAR enrichment completes, Diario and Statistiche show pending states and do not invent semantic diary data.
- Core Ingestion completion is enough to show/open the Viaggio. HAR/raw completion is not required for `remoteTripId`.
- The backend inline core response must include `trip_id` whenever `core_status=COMPLETED`.
- If the backend reaches `core_status=COMPLETED` without a materialized Trip, the API must fail explicitly rather than returning `trip_id=null`.
- The SyncQueue remains responsible for upload/sync state only. It does not directly navigate.
- The UI observes the synchronization snapshot and opens Dettaglio Viaggio once when it sees a newly completed Core with `remoteTripId`.
- The UI must guard against repeated automatic navigation for the same `remoteTripId`.
- Dettaglio Viaggio loads the diary read model first.
- If the diary read model is already processed, Dettaglio Viaggio does not open an SSE stream.
- If the diary read model is not processed, Dettaglio Viaggio opens a foreground SSE stream scoped to that Viaggio.
- SSE is used only while the app is open and the Dettaglio Viaggio page is visible.
- The SSE event is a wake-up signal, not source of truth.
- On `diary_enriched`, the mobile refetches the diary read model and updates all tabs.
- The SSE endpoint is scoped to one Viaggio:

```text
GET /api/mobility/trips/{trip_id}/events
Accept: text/event-stream
```

- The event shape is:

```text
event: diary_enriched
data: {"trip_id":123}
```

- The backend can implement SSE with HTTP streaming. The first implementation is demo/foreground oriented, not app-closed delivery.
- Preferenza Privacy is global for the authenticated user.
- Preferenza Privacy is stored independently from individual Viaggi.
- Preferenza Privacy is not snapshotted onto trips in this iteration.
- Supported Livelli Privacy are `precise`, `approximate`, and `aggregated`.
- The backend exposes dedicated privacy settings endpoints:

```text
GET /api/privacy/settings
PUT /api/privacy/settings
```

- The settings request/response shape is:

```json
{
  "privacy_level": "precise"
}
```

- Backend persistence uses a dedicated `UserPrivacySettings` one-to-one model rather than a field on the Django user model.
- The profile/settings UI is reachable from the drawer.
- The profile/settings UI shows name, email, privacy selector, saving/error state, and logout.
- The privacy preference is saved backend-side and reread when the profile/settings page opens.
- Existing authentication continues to use mobile Bearer tokens.
- Existing diary and track endpoints remain the read source for map, timeline and statistics.

## Testing Decisions

- Good tests should verify external behavior at API, cubit/service, queue, and widget seams; avoid asserting private helper call order.
- Backend privacy settings tests should use authenticated API requests and verify default creation, reading, updating, invalid privacy levels, and user isolation.
- Backend Core Ingestion tests should assert that completed inline core responses include a non-null `trip_id`.
- Backend Core Ingestion tests should assert that a completed core without a Trip fails explicitly.
- Backend SSE tests should verify authorization, trip ownership, event-stream content type, and emission of `diary_enriched` when the diary is already or becomes enriched.
- Mobile privacy service/cubit tests should fake the privacy settings API and cover loading, saving, invalid/error states, and persistence of selected value in UI state.
- Mobile profile widget tests should cover display of name/email and privacy selector behavior.
- Mobile Dettaglio Viaggio state tests should fake the diary/track services and cover processed, pending, empty, and error states.
- Mobile Dettaglio Viaggio tests should verify that pending diaries show base map/pending UI and do not show semantic statistics.
- Mobile statistics tests should verify duration, movement/stopped time, distance and activity distribution calculations from segment DTOs.
- Mobile automatic navigation tests should verify that the UI opens Dettaglio Viaggio once when Core completes with `remoteTripId`.
- Mobile automatic navigation tests should verify no navigation when Core is not completed or `remoteTripId` is absent.
- Mobile SSE tests should fake an event stream and verify that `diary_enriched` triggers a diary refetch.
- Mobile SSE lifecycle tests should verify that the stream is opened only for pending diaries and closed when the page is disposed or enrichment completes.
- Existing prior art includes inline core ingestion API tests, ingestion state model tests, trip track tests, trip package builder tests, trip sync queue tests, trip track cubit tests, and trips list cubit tests.
- The highest-value end-to-end mobile seam is Dettaglio Viaggio state behavior with fake services, because it proves map/diary/statistics update together from the same read model.

## Out of Scope

- Applying privacy transformations to the actual map, diary or exported data.
- Exporting or sharing a privacy-aware diary.
- Persisting privacy snapshots on Viaggi.
- Aggregating multiple Viaggi into a full day view.
- Weekly/monthly analytics, heatmaps, repeated-route analytics, or cross-trip statistics.
- Editing Segmenti di Mobilita or Luoghi Significativi manually.
- Native push notifications through Firebase/APNs.
- App-closed or background delivery of enrichment events.
- WebSocket bidirectional messaging.
- Replacing backend read models with event payloads.
- Changing the HAR model, HAR adapter or raw sensor upload format.
- Changing Core Ingestion or Raw Sensor Ingestion semantics beyond enforcing the completed-core `trip_id` invariant.
- Dashboard web work.

## Further Notes

- This PRD follows the domain language in `CONTEXT.md`: Viaggio, Core Ingestion,
  Raw Sensor Ingestion, Viaggio Sincronizzato, Traiettoria del Viaggio,
  Arricchimento del Viaggio, Diario della Mobilita, Segmento di Mobilita,
  Timeline del Viaggio, Statistiche del Viaggio, Preferenza Privacy and Livello
  Privacy.
- This PRD respects the existing ADR that the frontend discovers HAR enrichment
  by refetching a segmented diary read model. The new SSE stream changes the
  wake-up mechanism, not the source of truth.
- The foreground SSE decision is recorded in ADR 0016.
- The user-scoped privacy settings decision is recorded in ADR 0015.
- The local PRD is ready for an agent to implement. Publishing to GitHub Issues
  could not be completed from this environment because the GitHub CLI is not
  installed and the repo does not currently declare an alternative issue tracker
  configuration for the agent skills.
