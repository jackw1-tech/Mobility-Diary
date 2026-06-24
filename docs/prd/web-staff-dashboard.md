# PRD: Piattaforma Web Staff per il Diario della Mobilita

## Problem Statement

Il progetto ha gia backend e app mobile per raccogliere, sincronizzare e trasformare Viaggi in Diario della Mobilita, ma manca una Piattaforma Web per gli Operatori Web. Serve una dashboard staff che permetta di analizzare utenti, viaggi, tracce, segmenti, timeline e statistiche senza usare l'app mobile e senza esporre questa vista agli utenti normali.

## Solution

Costruire una Piattaforma Web in `web/` con Vue, TypeScript, Vue Router, Leaflet/OpenStreetMap e CSS leggero ispirato al design system Uber. La dashboard avra autenticazione web separata con JWT access + refresh token, accessibile solo a utenti Django staff/superuser.

Flusso principale:

```text
Login staff
  -> Lista utenti non-staff
    -> click utente
      -> Lista viaggi dell'utente
        -> click viaggio
          -> Dashboard viaggio: mappa, timeline, statistiche
```

## User Stories

1. As an Operatore Web, I want to log in with real staff credentials, so that dashboard access is restricted.
2. As an Operatore Web, I want dashboard auth to be separate from mobile auth, so that mobile users are not affected.
3. As an Operatore Web, I want refresh-token sessions, so that I can keep working without logging in repeatedly.
4. As an Operatore Web, I want to log out and revoke my refresh token, so that my session is closed server-side.
5. As an Operatore Web, I want to see all non-staff users, so that I can choose a Proprietario del Viaggio to inspect.
6. As an Operatore Web, I want inactive users to remain visible, so that historical Viaggi remain analyzable.
7. As an Operatore Web, I want staff/superuser accounts excluded from the analyzable user list, so that operators are not mixed with mobile users.
8. As an Operatore Web, I want each user row to show email, name, trip counts, processed counts, last trip, and total distance, so that I can quickly pick relevant data.
9. As an Operatore Web, I want to open one user and see their Viaggi, so that analysis starts from a clear owner context.
10. As an Operatore Web, I want server-side filters for Viaggi by date range, status, processed state, and track availability, so that large lists stay manageable.
11. As an Operatore Web, I want to open a Viaggio and see a breadcrumb with the user email and trip id, so that I do not lose context.
12. As an Operatore Web, I want to see the full trip trace on a map, so that I can inspect the route.
13. As an Operatore Web, I want movement segments color-coded by activity, so that walking, biking, running, and vehicle movement are visually distinct.
14. As an Operatore Web, I want STOP segments excluded from map markers for now, so that significant-place work is not implied before it is ready.
15. As an Operatore Web, I want STOP segments shown neutrally in the timeline, so that the diary still shows pauses without place semantics.
16. As an Operatore Web, I want a single dashboard detail view instead of tabs, so that map, timeline, and statistics are visible together.
17. As an Operatore Web, I want client-side filters in the trip detail by activity and time interval, so that I can inspect a subset of the diary.
18. As an Operatore Web, I want statistics for the currently open Viaggio, so that I can summarize duration, distance, movement time, stopped time, and activity split.
19. As an Operatore Web, I want Italian UI labels, so that the dashboard matches the project relation and demo language.
20. As an Operatore Web, I want URL routes like `/users/:id/trips/:tripId`, so that refresh/back/forward work naturally in the SPA.
21. As an Operatore Web, I want a clean black-white-grey dashboard style, so that the interface feels professional and focused.
22. As an Operatore Web, I want functional colors only for activities, so that map interpretation remains clear.
23. As a developer, I want a separate `/api/web/...` namespace, so that staff-global endpoints cannot be confused with mobile user-scoped endpoints.
24. As a developer, I want backend responses to include minimal user attribution, so that the dashboard can distinguish Proprietari del Viaggio.
25. As a developer, I want this first implementation to avoid privacy comparison and global analytics, so that the initial scope stays deliverable.

## Implementation Decisions

- Create a new Vue + Vite + TypeScript SPA under `web/`.
- Use Vue Router for real client-side routes.
- Use Leaflet with OpenStreetMap tiles for maps.
- Use lightweight CSS, adapted from the local Uber-inspired design system: black/white/grey palette, pill buttons, square grey inputs, dense dashboard layout.
- Use functional activity colors on the map despite the mostly monochrome UI.
- Use Italian display text.
- Add `PyJWT` or equivalent lightweight JWT support to the backend.
- Keep existing mobile bearer-token auth unchanged.
- Add separate web-dashboard auth under `/api/web/auth/...`.
- Web auth issues access + refresh JWTs.
- Refresh tokens are stored server-side, revocable, and rotated on refresh.
- Store both access and refresh tokens in `localStorage` for the first version.
- Add logout that revokes the active refresh token.
- Staff access allows `is_staff=True` or `is_superuser=True`.
- Add web staff endpoints under `/api/web/...`.
- Dashboard user list returns non-staff users only, including users with zero Viaggi and inactive users.
- Viaggi are loaded per selected user from the backend, not by loading all trips client-side.
- Trip list filters are server-side: `from`, `to`, `status`, `processed`, `has_track`.
- Trip detail data uses existing track and diary read models, adapted to staff-global access.
- Detail filters are client-side: activity and time interval.
- SignificantPlace data is not shown on the map and should not drive first-version UI behavior.
- Statistics are computed for the currently open Viaggio only.
- No frontend Docker integration in the first version; run with `npm run dev`.

## Testing Decisions

- Primary backend test seam: web API behavior through Django/Ninja test client.
- Test web auth externally: staff login succeeds, non-staff login is rejected, refresh rotates, logout revokes.
- Test web user list externally: non-staff users appear, staff/superusers do not, inactive users appear with status metadata.
- Test trip list externally: only selected user's Viaggi are returned and filters affect results.
- Test web track/diary access externally: staff can read any user's trip; unauthenticated/non-staff access fails.
- Reuse prior art from existing backend tests for mobile auth, privacy settings, trip list, trip track, diary, and SSE behavior.
- Primary frontend test seam: API client + routed page behavior with mocked API responses.
- Frontend tests should assert visible behavior: login flow, users list, trip list filters, map/timeline/stat panels receiving expected data.
- Avoid testing implementation details like internal component state where rendered UI or API calls are enough.

## Out of Scope

- Luoghi significativi sulla mappa.
- Creazione o modifica manuale dei luoghi significativi.
- Confronto traccia reale vs anonimizzata/perturbata.
- Privacy-aware diary read model.
- Statistiche globali aggregate su tutti gli utenti/viaggi.
- Heatmap e analytics avanzata.
- Registrazione staff dalla dashboard.
- Cookie `HttpOnly`.
- Containerizzazione del frontend.
- Sostituzione dell'autenticazione mobile esistente.
- Editing o cancellazione utenti/viaggi dalla dashboard.

## Further Notes

Decisioni gia documentate negli ADR:

- Auth web separata con JWT staff.
- Vista Staff Globale distinta dalle API mobile user-scoped.

Il requisito piu importante da preservare e la separazione: mobile rimane personale e user-scoped; la Piattaforma Web e staff-only e globale.
