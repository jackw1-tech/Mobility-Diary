# HAR Labels Are Aggregated Into Readable Mobility Segments

Status: accepted

HAR predictions are produced at sensor-window granularity, but the diary should expose readable mobility segments rather than one row per window. The final enrichment uses GPS and state transitions to define stop/move spans, keeps stops as idle, and splits movement spans only on meaningful activity-label changes.

**Consequences**

The HAR pipeline should smooth or merge isolated short label changes before writing `MobilitySegment` rows. This keeps the diary aligned with the project requirement of human-readable intervals such as a bike movement, a university stay, or a walking segment, instead of exposing noisy five-second model outputs as product data.
