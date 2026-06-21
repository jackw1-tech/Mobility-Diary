# Make Inline Core Ingestion The Primary Path

Status: accepted

Core Ingestion carries the small, product-critical evidence needed to make a
Viaggio visible and map-ready: GPS points and state transitions. We decided that
new mobile clients should send this core evidence directly to Django in one
idempotent request, and that Django should materialize the core synchronously
inside that request, rather than using the presign/PUT/confirm/complete-core
object-storage flow and Celery polling designed for larger raw sensor payloads.

**Considered Options**

- Keep GPS points and state transitions on the existing presigned part upload
  flow for uniformity with raw sensor evidence.
- Introduce synchronous inline Core Ingestion as the primary path, while keeping
  raw sensor evidence on presigned object-storage upload.

**Consequences**

Core completion can become much faster and simpler for the mobile app, because a
small payload no longer pays multiple HTTP round trips, object-storage writes,
part confirmations, Celery scheduling, and polling before a Viaggio can expose a
map. The backend still keeps a single `TripIngestion` with separate
`core_status` and `raw_status`, and `client_session_id` remains the idempotency
key. Raw Sensor Ingestion keeps the presigned upload path because raw payloads
can grow and should not pass through Django or Postgres as blobs.

The inline core request owns validation, idempotent `Trip` creation,
materializing GPS points and state transitions, building the derived path, and
marking `core_status=COMPLETED` in one transaction. This deliberately removes
Celery and status polling from the happy path that unlocks the map.

Inline Core Ingestion still accepts a core payload with only GPS points or only
state transitions, because either source can be enough to synchronize the
Viaggio. An empty core payload is invalid. The map is a narrower capability:
it is available only when the accepted core payload contains enough valid GPS
evidence to derive a trajectory.

The inline arrays keep the same record shape currently used by
`gps_points.json.gz` and `state_transitions.json.gz`. The migration changes the
transport boundary, not the meaning or field names of the core evidence.

The mobile sync queue still treats raw upload as part of the same local
`SyncJob`: after inline core completion, it may continue in the same processing
pass by uploading raw sensor evidence through the presigned object-storage flow.
The product value unlocked by core completion is not blocked by raw upload
success or failure.

The inline core request also declares `expected_raw_parts`. If no raw parts are
expected, the backend initializes `raw_status=COMPLETED`; otherwise it keeps
`raw_status=PENDING` so the same `TripIngestion` can receive raw sensor evidence
through the existing presigned endpoints after core completion.

The existing presigned core endpoints remain available only as legacy
compatibility for older clients. New product work should not build on presigned
core parts, and the mobile app should use the inline core endpoint as its
primary path. Presigned upload remains the primary path for raw sensor evidence.

The inline core payload has a hard maximum size of 1 MB, measured on the whole
decoded JSON request body, including metadata and core evidence arrays. This
keeps the endpoint clearly in the "small core evidence" category while leaving
generous room over the observed GPS/state-transition payload sizes. Requests
above that limit are rejected as too large instead of silently falling back to a
heavier ingestion path.

The inline core response returns enough information for the mobile app to update
the UI without an immediate status poll: `ingestion_id`, `trip_id`,
`core_status`, `raw_status`, materialized counts, `distance_meters`, and
`map_available`. `map_available` is the explicit product signal that the backend
derived a usable trajectory from the submitted GPS evidence.

Retries against the inline core endpoint are idempotent by
`client_session_id`, but the client must also submit a `core_payload_sha256`
computed over the canonical inline core payload. If the same
`client_session_id` is retried with the same hash, the endpoint returns the
existing result or converges to it. If the same `client_session_id` is retried
with a different hash, the endpoint returns a conflict rather than silently
rewriting a session. If Core Ingestion is already completed, the endpoint
returns the existing `ingestion_id`, `trip_id`, `core_status`, and `raw_status`.
If core is still pending, receiving, received, or failed retryably, the backend
may process the submitted core payload again and converge to completed. If a
legacy queued or processing state is observed, the endpoint returns the current
state without starting a second materialization. A final core failure remains a
conflict and requires an explicit recovery path rather than silently mutating the
failed ingestion.

The backend recalculates the submitted core hash from a stable representation of
the request body excluding `core_payload_sha256`. A hash mismatch means the
client did not sign the payload it actually sent and is rejected as a bad
request. A later request for the same `client_session_id` with a different core
hash is rejected as a conflict.

The hash is computed on the UTF-8 bytes of the deterministic inline core JSON
body before `core_payload_sha256` is inserted. It is not computed on compressed
HTTP transport bytes. For verification, the backend removes
`core_payload_sha256`, rebuilds the same compact stable JSON representation, and
compares the resulting hash with the submitted value.
