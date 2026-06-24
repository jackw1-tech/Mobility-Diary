# Web Dashboard Uses Separate Staff JWT Auth

The mobile app already uses opaque bearer tokens, but the Piattaforma Web needs a distinct authentication boundary because only trusted staff users should access dashboard data. We will keep mobile authentication unchanged and add a separate web-dashboard JWT flow that issues tokens only to Django staff or superuser accounts.

**Considered Options**

- Reuse the existing mobile bearer token flow for the web dashboard.
- Replace all authentication with JWT.
- Add a separate JWT flow for the web dashboard only.

**Consequences**

Mobile clients keep their stable contract, while dashboard access can enforce staff-only rules without leaking that policy into the mobile API surface.
