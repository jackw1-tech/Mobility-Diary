# Raw Sensor Evidence Is Retained After HAR Success

Status: accepted

Raw sensor evidence should be retained in object storage after successful HAR processing for the current project phase. The retained blobs support debugging, repeatable inference, model comparison, metric calculation, and explanation in the project report.

**Considered Options**

- Delete raw sensor blobs immediately after successful diary enrichment.
- Retain raw sensor blobs for now, with cleanup kept behind an explicit retention policy.

**Consequences**

`HAR_CLEANUP_ENABLED` should remain disabled for now. The system can later add a lifecycle or event-driven cleanup policy, but successful HAR processing must not automatically remove the raw evidence in the current implementation.
