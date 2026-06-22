# HAR Failures Preserve Raw Evidence For Retry

Status: accepted

HAR processing failures must not delete raw sensor evidence. Retryable failures move Raw Sensor Ingestion to `FAILED_RETRYABLE` and allow Celery or an operator-initiated recovery path to run the same evidence again; final failures move it to `FAILED_FINAL` while preserving the uploaded blobs for diagnosis.

**Consequences**

The HAR task may clean up raw blobs only after a successful enrichment and only when a separate retention policy enables cleanup. Any failure path must keep object-storage evidence intact so the mobile app does not need to re-upload sensor windows after backend-side problems.
