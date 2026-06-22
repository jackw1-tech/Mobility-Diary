# Mobility Segments Persist Derived PostGIS Paths

Status: accepted

Movement Segmenti di Mobilita should persist their derived PostGIS LineString path as part of the diary read model. The worker fuses StateTransition events, GPS samples, and HAR windows by time: StateTransition decides stop/move spans, HAR assigns activity labels inside movement spans, GPS provides geometry and distance, and MobilitySegment stores the final derived interval.

**Considered Options**

- Store only segment timestamps and calculate movement geometry from GPS points on every map request.
- Persist the derived movement geometry on each MobilitySegment when the diary is regenerated.

**Consequences**

The segmented map read model becomes simple and fast for the frontend, because each movement segment already carries the geometry needed for rendering. This duplicates derived geometry relative to raw GPS points, but the duplication belongs to the product read model and is regenerated idempotently whenever HAR enrichment is rerun. Stop segments use SignificantPlace center/radius/dwell instead of a fake movement path.
