# Raw Sensor Evidence Stays Out Of Postgres

Status: accepted

Raw sensor evidence is used by Celery as input for HAR processing, but the raw matrices should not be persisted in Postgres as part of the diary model. The worker reads sensor-window blobs from object storage, builds temporary in-memory windows for the model, and persists only the product result: mobility segments, activity labels, significant places, job metadata, and derived statistics.

**Considered Options**

- Store raw sensor matrices in Postgres so the existing pipeline can read `SensorWindow` rows directly.
- Keep raw sensor matrices in object storage and adapt the HAR pipeline to consume downloaded windows in memory.

**Consequences**

The HAR pipeline needs an explicit input boundary instead of relying on `trip.sensor_windows` as its source. In exchange, Postgres remains focused on the readable mobility diary, while bulky and privacy-sensitive sensor evidence stays in object storage.
