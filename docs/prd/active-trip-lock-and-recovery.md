# PRD: Active Trip Lock And Recovery

## Problem Statement

Users can currently start recording a Viaggio from the mobile app, but the backend only learns about that recording when the app later stops and uploads the final Core Ingestion. This creates two user-facing risks: the same account can record multiple overlapping Viaggi from different devices, and an interrupted app can leave the user unsure whether the Viaggio is recoverable or lost.

The app needs a backend-backed Viaggio in Corso from the moment the user starts recording, while still keeping incomplete or abandoned recordings out of the normal Diario della Mobilita.

## Solution

When a user taps Start, the mobile app must contact the backend before sensors begin. The backend creates an in-progress TripIngestion as the durable Viaggio in Corso lock for that Proprietario del Viaggio, tied to the Dispositivo Origine del Viaggio and the local SQLite session. If an active TripIngestion already exists, the backend rejects the new start with enough information for the frontend to either recover the local session or explain that another device is already recording.

The true visible Viaggio is still created only when the final Core Ingestion arrives at Stop. That final core upload validates the `ingestion_id`, `client_session_id`, and `device_id`, materializes the Viaggio, and closes the backend lock atomically. Heartbeats keep the Viaggio in Corso alive while recording. A Viaggio in Corso becomes abandoned after 24 hours without heartbeat, or immediately when the Dispositivo Origine del Viaggio no longer has the matching SQLite session needed for recovery.

## User Stories

1. As a mobile user, I want Start to be blocked when my account already has a Viaggio in Corso, so that I cannot accidentally create overlapping Viaggi.
2. As a mobile user, I want Start to require backend connectivity, so that the app can guarantee the account-wide active Viaggio rule before recording begins.
3. As a mobile user, I want a clear message when I try to start while another device is already recording, so that I understand why the app will not start.
4. As a mobile user, I want my interrupted recording to resume when the same device still has the local SQLite session, so that an app restart does not lose my Viaggio.
5. As a mobile user, I want the app to refuse cross-device recovery, so that a second phone cannot corrupt or close a Viaggio started elsewhere.
6. As a mobile user, I want the app to abandon an unrecoverable same-device Viaggio immediately when SQLite no longer has the session, so that I can start a new Viaggio without waiting 24 hours.
7. As a mobile user, I want an unrecoverable active Viaggio from another device to remain blocked, so that one device cannot abandon another device's active recording.
8. As a mobile user, I want abandoned Viaggi to stay out of my normal diary and trip list, so that incomplete technical records do not pollute my Diario della Mobilita.
9. As a mobile user, I want Stop to require backend completion, so that the active lock is released only when the backend has received the final core evidence.
10. As a mobile user, I want Stop offline to stop local sensors but show a pending sync state, so that the app does not keep collecting after I asked it to stop.
11. As a mobile user, I want pending Stop to retry automatically when connectivity returns, so that I do not need to babysit the upload.
12. As a mobile user, I want a pending Stop to keep blocking new Start actions, so that I do not create overlapping Viaggi before the backend lock closes.
13. As a mobile user, I want retryable upload failures to keep retrying, so that temporary network or backend problems do not lose my Viaggio.
14. As a mobile user, I want permanent core failures to release the active lock and stay hidden from the diary, so that a non-recoverable recording does not block my account forever.
15. As a mobile user, I want the app to show an understandable error when a Viaggio cannot be recovered, so that I know what happened and can move on.
16. As a mobile user, I want tracking to continue offline after a successful Start, so that temporary connectivity loss during a Viaggio does not stop local recording.
17. As a mobile user, I want the app to send lightweight heartbeats while tracking, so that the backend knows the Viaggio in Corso is still alive.
18. As a mobile user, I want heartbeat to happen on foreground resume, so that returning to the app quickly refreshes the backend lock.
19. As a mobile user, I want the app to detect active backend recordings at launch, so that it can reconcile backend and SQLite state before I start or resume.
20. As a mobile user, I want a stable Dispositivo Origine del Viaggio identity, so that backend recovery rules are consistent across app sessions.
21. As a backend operator, I want TripIngestion to hold incomplete recording state, so that visible Viaggi remain clean diary entries.
22. As a backend operator, I want exactly one active non-abandoned TripIngestion per Proprietario del Viaggio, so that concurrency is enforced server-side.
23. As a backend operator, I want Start conflict responses to include the active ingestion identity and device information, so that the frontend can choose the correct recovery UI.
24. As a backend operator, I want active ingestion abandonment to be evaluated transactionally during Start, so that stale locks are released safely before creating a new lock.
25. As a backend operator, I want an explicit heartbeat timestamp, so that 24-hour abandonment does not depend on interpreting upload side effects.
26. As a backend operator, I want the final core payload to validate ingestion identity, local session identity, and device identity, so that a stale payload cannot close the wrong lock.
27. As a backend operator, I want permanent final failures to release the active lock, so that broken payloads do not block future recording.
28. As a backend operator, I want abandoned in-progress ingestions to remain auditable, so that support and debugging can inspect what happened without showing it in the diary.
29. As a developer, I want the new behavior covered at API and repository seams, so that lock and recovery regressions are caught without brittle implementation tests.
30. As a developer, I want the existing sync queue behavior to adapt to pre-created ingestions, so that raw upload, polling, and retry behavior continue to work.
31. As a developer, I want local SyncJob state to preserve the remote ingestion id after Start, so that Stop can complete the same TripIngestion instead of creating a new one.
32. As a developer, I want the app to generate and persist a stable device id, so that the same-device and other-device cases are deterministic in tests and production.
33. As a developer, I want active-ingestion status to be available from the backend, so that app startup can reconcile remote and local state.
34. As a product owner, I want this feature to protect diary quality, so that analytics and trip lists only reflect synchronized, meaningful Viaggi.
35. As a product owner, I want the UX to be strict but understandable, so that users know why Start or Stop is blocked and what will happen next.

## Implementation Decisions

- Respect ADR 0001: Active trip locks use TripIngestion.
- Do not create a visible Viaggio at Start.
- Use TripIngestion as the durable backend record for Viaggio in Corso, active lock, device-origin check, heartbeat, abandonment, and recovery.
- Add backend fields to TripIngestion for recording lifecycle timestamps: recording started, recording closed, recording abandoned, and last heartbeat/last seen.
- Treat an active TripIngestion as one with a recording start timestamp and no recording closed or abandoned timestamp.
- Enforce one active non-abandoned TripIngestion per Proprietario del Viaggio in backend transactional logic.
- Enforce the active lock server-side even if the frontend fails to block.
- Start requires backend connectivity and must happen before sensors begin.
- Stop requires backend completion of the final Core Ingestion to release the backend lock.
- Tracking may continue offline after a successful Start.
- Stop offline stops sensors locally, creates or updates a pending sync state, and keeps the backend lock active until the final core upload succeeds, fails permanently, or is abandoned by rules.
- The mobile app must generate a stable device id once and persist it securely.
- The stable device id replaces the current placeholder device id for acquisition sessions and ingestion payloads.
- The Dispositivo Origine del Viaggio is the only device allowed to resume or abandon a same-device unrecoverable active TripIngestion.
- Recovery requires both backend same-device confirmation and matching local SQLite session.
- SQLite local state has priority for recovery. If the backend reports an active ingestion on the same device but local SQLite no longer has the matching session, the app may abandon the backend ingestion immediately.
- A different device must not abandon another device's active TripIngestion before the 24-hour timeout.
- A Viaggio in Corso becomes abandoned after 24 hours without heartbeat.
- Abandoned in-progress ingestions must not appear in normal diary, trip list, personal analytics, or map views.
- Add a Start endpoint that creates a new active TripIngestion, abandons stale active ingestions when allowed, or returns a conflict for an existing active ingestion.
- Add an Active endpoint for app launch reconciliation.
- Add a Heartbeat endpoint that updates last seen for the active ingestion.
- Add an Abandon endpoint for the same-device no-local-SQLite case.
- Keep the existing final core ingestion endpoint as the materialization path, but require it to close a pre-created active ingestion when `ingestion_id` is supplied.
- The final core payload must include and validate `ingestion_id`, `client_session_id`, and `device_id`.
- The backend must reject final core payloads whose ingestion id, client session id, device id, owner, or active status do not match.
- The existing inline core idempotency behavior should remain for retries of the same final payload.
- The sync queue must use the remote ingestion id saved at Start instead of assuming the remote ingestion is unknown until Stop.
- Local SQLite acquisition session state needs to persist the remote ingestion id or equivalent remote active-recording reference.
- Local SyncJob state should preserve remote ingestion id so raw upload and status polling continue from the same backend ingestion.
- Heartbeats should be sent every 5 minutes while tracking and immediately when the app returns to foreground.
- Heartbeat failure should not stop local tracking, but should leave the backend lock vulnerable to the 24-hour abandonment rule if connectivity never returns.
- Start conflict UI should distinguish same-device recoverable, same-device unrecoverable, and other-device active cases.
- Same-device recoverable conflict should resume the local session rather than starting a new one.
- Same-device unrecoverable conflict should abandon the backend active ingestion and allow a new Start.
- Other-device conflict should block Start with a message that another device has a Viaggio in Corso.
- Retryable final sync failures keep the lock active and the UI in pending sync.
- Permanent final sync failures release the active lock, do not create a visible diary entry, and surface a dismissible non-recoverable state to the user.

## Final Endpoint Contracts

- `POST /api/ingestion/trips/start`: creates the account-scoped active `TripIngestion` before sensors start. Returns `200` with `ingestion_id`, `client_session_id`, `device_id`, `recording_started_at`, and `already_exists`; returns structured `409` with `active_ingestion` when another active recording blocks Start.
- `GET /api/ingestion/trips/active`: returns the current active ingestion for launch reconciliation, or `404` when the account has no active recording.
- `POST /api/ingestion/trips/{ingestion_id}/heartbeat`: accepts `client_session_id` and `device_id`, updates `last_seen_at`, and rejects wrong-session, wrong-device, closed, or abandoned ingestions.
- `POST /api/ingestion/trips/{ingestion_id}/abandon`: same-device escape hatch for the no-local-SQLite case. It marks `recording_abandoned_at` and releases the active lock without creating a visible `Trip`.
- `POST /api/ingestion/trips/core`: remains the final Core Ingestion materialization path. When `ingestion_id` is present, the backend validates owner, `client_session_id`, and origin `device_id`, materializes the visible `Trip`, and sets `recording_closed_at` atomically. Legacy inline core without `ingestion_id` remains supported for compatibility.
- Permanent core failure returns a terminal `409`, sets `recording_closed_at` when the failed ingestion was active, and does not create a visible `Trip`. Retryable core failure leaves the active lock open for retry or abandonment.

## User-Facing Copy

- Start cannot reach backend: `Serve connessione al backend per avviare un nuovo viaggio.`
- Other-device active lock: `Hai gia' un viaggio in corso su un altro dispositivo`
- Pending Stop/core sync: `Hai un viaggio in chiusura. Attendi la sincronizzazione prima di iniziarne un altro.`
- Non-recoverable final failure: panel title `Viaggio non recuperabile`, subtitle `La chiusura e fallita definitivamente`, with a dismiss action that hides the warning without deleting local audit state.

## Testing Decisions

- Prefer high-level behavior tests over implementation-detail tests.
- Backend API tests are the primary seam for active-lock behavior because the single-active guarantee must be enforced server-side.
- Backend API tests should cover successful Start, duplicate Start conflict, stale active abandonment after 24 hours, same-device immediate abandonment, other-device rejection, heartbeat updates, active status lookup, and final core validation.
- Backend final core tests should cover successful materialization closing the active lock, idempotent retry, mismatched ingestion id, mismatched client session id, mismatched device id, failed-final lock release, and retryable failure lock retention.
- Mobile repository/cubit tests are the primary seam for Start/Stop UX behavior because they capture user-visible state transitions without over-testing widgets.
- Mobile repository/cubit tests should cover Start success, Start offline failure, duplicate active on other device, recoverable same-device resume, same-device no-SQLite abandonment, Stop online completion, Stop offline pending sync, and retryable/permanent sync outcomes.
- Mobile sync queue tests should adapt existing coverage that currently expects inline core to create the remote ingestion; new tests should verify it posts final core against an existing remote ingestion id.
- Mobile ingestion API tests/fakes should cover new Start, Active, Heartbeat, Abandon, and final core payload shape.
- Local database tests should cover persisting remote ingestion id on acquisition sessions and preserving it through Stop and SyncJob creation.
- Existing prior art includes the inline core ingestion API tests, TripSyncQueueImpl tests, AcquisitionRepositoryImpl tests, AcquisitionCubit tests, and AcquisitionLocalDatabase tests.
- Tests should assert external statuses, HTTP responses, persisted lifecycle fields, and user-facing repository/cubit states rather than private helper calls.
- Time-based abandonment should use controllable timestamps or frozen time in backend tests.
- Device-origin behavior should use explicit stable device ids in tests instead of platform-specific device APIs.

## Out of Scope

- Cross-device takeover or continuation of a Viaggio in Corso.
- Showing abandoned Viaggi in normal diary, trip list, analytics, or mobile map views.
- Manual user-facing recovery of remote-only trip data without SQLite evidence.
- A full admin UI for abandoned ingestions.
- Real-time streaming of GPS points to the backend during a Viaggio.
- Allowing Start while offline.
- Allowing Stop to fully complete while offline.
- Changing significant-place recognition, personal analytics, or trip detail presentation except to ensure abandoned in-progress records stay hidden.
- Solving OS-level background execution guarantees beyond the existing tracking resilience work.

## Further Notes

- Current mobile behavior creates the backend TripIngestion only during Stop/sync via inline Core Ingestion. This PRD intentionally moves active-record creation to Start.
- The existing backend already has TripIngestion, client-session idempotency, inline core materialization, raw sensor upload, and sync polling concepts. The feature should extend these instead of introducing a separate active-trip table unless implementation proves the model too constrained.
- The old create-ingestion endpoint exists but is not used by the current inline mobile flow. It may be adapted, replaced, or wrapped by a clearer Start endpoint.
- The PRD should be published to GitHub Issues with label `ready-for-agent`.
