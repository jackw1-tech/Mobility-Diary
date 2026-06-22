# Complete Raw Enqueues HAR Processing

Status: accepted

When all raw sensor parts for a Viaggio are confirmed, `complete-raw` should mark the raw phase as ready for processing and enqueue the final HAR task after the database transaction commits. The primary flow is event-driven so the diary can be enriched as soon as the mobile app finishes uploading raw sensor evidence; a periodic recovery task may later scan for stuck received ingestions if Redis or Celery were unavailable at the enqueue boundary.

**Consequences**

`complete-raw` no longer represents a terminal success by itself. It becomes the transition from uploaded evidence to backend processing, and clients should keep polling until Raw Sensor Ingestion reaches `COMPLETED`, `FAILED_RETRYABLE`, or `FAILED_FINAL`.
