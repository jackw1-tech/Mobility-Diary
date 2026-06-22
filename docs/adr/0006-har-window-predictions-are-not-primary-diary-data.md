# HAR Window Predictions Are Not Primary Diary Data

Status: accepted

HAR processing should persist the final mobility diary as product data, while keeping per-run classifier details as lightweight job metadata. `MobilitySegment.activity_label` is the product-facing result; `HarJob.result` may record summary information such as window count, label distribution, classifier name, and confidence aggregates when available.

**Considered Options**

- Persist every per-window HAR prediction as its own queryable table.
- Persist final mobility segments as diary data and keep classifier diagnostics in `HarJob.result`.

**Consequences**

The backend can satisfy the diary, statistics, and reporting requirements without growing a second prediction data model too early. If detailed per-window debugging or visualisation becomes necessary, it can be added later as a deliberate analytics feature rather than as the primary diary representation.
