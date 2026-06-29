# Active trip locks use TripIngestion

Accepted.

When a mobile user starts recording, the backend creates or reuses a `TripIngestion` as the in-progress recording record instead of creating a visible `Trip` immediately. A real `Trip` is materialized only when the final core ingestion arrives; that same final core submission closes the in-progress recording lock atomically.

This keeps incomplete, abandoned, and retrying recordings out of the user diary while still giving the backend a durable account-wide lock, a device-origin check, heartbeat-based abandonment, and a recovery anchor for interrupted apps.

## Consequences

Only one non-abandoned in-progress ingestion may exist per trip owner. A recording can be resumed only by the device that started it and only if that device still has the local SQLite session. If no heartbeat is received for 24 hours, the in-progress ingestion may be marked abandoned and must not appear in normal diary or trip lists.

Starting and stopping a recording both require backend connectivity. After a successful start, the mobile app may keep collecting evidence offline, but the final stop must deliver the core ingestion so the backend can materialize the `Trip` and close the in-progress lock atomically.

If the final core ingestion fails permanently, the in-progress ingestion releases the active-trip lock but does not create a visible diary entry. Retryable failures keep the lock active until the final core ingestion succeeds, fails permanently, or becomes abandoned by the 24-hour heartbeat rule.

The final core payload identifies the in-progress ingestion with `ingestion_id`, `client_session_id`, and `device_id`. The backend validates all three before materializing the `Trip` or closing the lock.

Terminal final-core conflicts must persist their lifecycle update before returning `409`. In practice, handlers that release `recording_closed_at` for a `FAILED_FINAL` ingestion return a structured status response instead of raising after the save, so the lock release is not rolled back with the error response.

Local SQLite has priority for recovery. If the backend reports an active ingestion for the current device but the device no longer has the matching local session, the app may ask the backend to mark that ingestion abandoned immediately instead of waiting for the 24-hour timeout.
