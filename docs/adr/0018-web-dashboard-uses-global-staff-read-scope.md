# Web Dashboard Uses Global Staff Read Scope

The mobile API is intentionally scoped to the authenticated user's own Viaggi, but the Piattaforma Web is a staff dashboard for demonstration and analysis. Web-dashboard endpoints will therefore expose a global read scope across all users, guarded by staff-only JWT authentication, instead of reusing the mobile user-scoped query semantics.

**Consequences**

Dashboard routes must never be protected only by mobile bearer authentication, and web API responses should include enough user/session metadata for an Operatore Web to distinguish Viaggi from different users.
