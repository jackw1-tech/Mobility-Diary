# Raw Completion Means Diary Enrichment

Status: accepted

Raw Sensor Ingestion is complete only after the uploaded raw sensor evidence has been processed into diary enrichment, not merely after the bytes are present in object storage. We keep `raw_status=RECEIVED` for "all raw parts are available" and reserve `raw_status=COMPLETED` for the point where HAR has produced activity labels and mobility segments for the already synchronized Viaggio.

**Considered Options**

- Treat raw upload confirmation as completion, and run HAR as a separate optional concern.
- Treat raw upload confirmation as received evidence, and make completion mean product-visible diary enrichment.

**Consequences**

`complete-raw` should enqueue or converge toward HAR processing instead of marking the raw phase completed immediately. Clients can distinguish "raw data safely uploaded" from "diary enriched", and retries can re-run HAR without requiring the mobile app to upload the same sensor evidence again.
