---
labels:
  - ready-for-agent
---

# Lista Proprietari Del Viaggio

## Parent

[PRD: Piattaforma Web Staff per il Diario della Mobilita](../prd/web-staff-dashboard.md)

## What to build

After an Operatore Web logs in, show the list of analyzable Proprietari del Viaggio. The list must come from staff-only web endpoints and include non-staff users only, including inactive users and users with zero Viaggi. Staff and superuser accounts must not appear as analyzable users.

Each row should give enough context to pick a user for analysis without becoming an account-management screen.

## Acceptance criteria

- [ ] The authenticated dashboard can load a list of non-staff users from the web API namespace.
- [ ] Staff and superuser accounts are excluded from the analyzable user list.
- [ ] Inactive non-staff users remain visible and are clearly distinguishable.
- [ ] Users with zero Viaggi appear in the list.
- [ ] User rows include email, first/last name when available, total trip count, processed trip count, latest trip timestamp, and total distance.
- [ ] Clicking a user navigates to that user's route in the Vue SPA.
- [ ] Unauthenticated requests and non-staff dashboard sessions cannot read the list.
- [ ] Tests cover the user-list visibility rules and summary fields through the web API.

## Blocked by

- [Staff Login E Sessione Web](0001-staff-login-e-sessione-web.md)
