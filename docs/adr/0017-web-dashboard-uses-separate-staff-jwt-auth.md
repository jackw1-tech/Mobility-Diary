# Web Dashboard Uses Separate Staff JWT Auth

The mobile app already uses opaque bearer tokens, but the Piattaforma Web needs a distinct authentication boundary because only trusted staff users should access dashboard data. We will keep mobile authentication unchanged and add a separate web-dashboard JWT flow that issues access and refresh tokens only to Django staff or superuser accounts. Refresh tokens are stored server-side, revocable, and rotated on refresh.

**Considered Options**

- Reuse the existing mobile bearer token flow for the web dashboard.
- Replace all authentication with JWT.
- Add a separate JWT flow for the web dashboard only.
- Use access tokens only.
- Use access and refresh tokens.
- Keep refresh tokens stateless.
- Store and revoke refresh tokens server-side.

**Consequences**

Mobile clients keep their stable contract, while dashboard access can enforce staff-only rules without leaking that policy into the mobile API surface. The web dashboard can keep sessions alive through refresh tokens, and the backend can revoke dashboard sessions, but refresh handling and token persistence become part of the dashboard auth contract from the first implementation.
