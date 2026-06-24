---
labels:
  - ready-for-agent
---

# Staff Login E Sessione Web

## Parent

[PRD: Piattaforma Web Staff per il Diario della Mobilita](../prd/web-staff-dashboard.md)

## What to build

Build the first end-to-end path for the Piattaforma Web: an Operatore Web can open the Vue dashboard, log in with real Django staff/superuser credentials, receive web-dashboard JWT access and refresh tokens, keep the session in browser storage, and log out with server-side refresh-token revocation.

This slice must keep mobile authentication unchanged. The new dashboard auth belongs under the separate web API namespace and must reject non-staff users.

## Acceptance criteria

- [ ] A staff or superuser account can log in from the web dashboard and reach an authenticated shell.
- [ ] A non-staff user cannot log in to the web dashboard even with valid credentials.
- [ ] Login returns access and refresh tokens for the web-dashboard auth flow.
- [ ] Refresh tokens are stored server-side, revocable, and rotated on refresh.
- [ ] Logout revokes the active refresh token and clears dashboard browser storage.
- [ ] The Vue app exists under `web/`, uses TypeScript and Vue Router, and has Italian UI copy.
- [ ] The dashboard stores access and refresh tokens in `localStorage` for this first version.
- [ ] Backend tests cover staff login, non-staff rejection, refresh rotation, and logout revocation through public API behavior.

## Blocked by

None - can start immediately
