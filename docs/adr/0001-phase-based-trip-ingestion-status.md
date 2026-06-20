# Split Trip Ingestion Status By Phase

Status: accepted

Trip ingestion is a single lifecycle for one viaggio, but core data and raw sensor
data complete at different times and unlock different product value. We decided
to replace the single `TripIngestion.status` field with explicit `core_status`
and `raw_status` fields, using the same status vocabulary for both phases, rather
than keeping `status` as a legacy aggregate.

**Considered Options**

- Keep `status` as a temporary aggregate mirrored from `core_status`.
- Remove `status` immediately and migrate all code to phase-specific status.

**Consequences**

The migration is more invasive now because models, API, admin, worker code, and
mobile polling must stop relying on `status`. In exchange, the model avoids a
long-lived ambiguous field and makes it clear that a viaggio can exist after
Core Ingestion completes even while Raw Sensor Ingestion is still pending.
Core Ingestion requires at least one confirmed core part. Raw Sensor Ingestion
may be absent; when no raw parts are expected, raw status is completed from the
start.
