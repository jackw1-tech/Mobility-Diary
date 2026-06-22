# HAR Enrichment Regenerates Derived Diary Entries

Status: accepted

Final HAR enrichment should be idempotent by regenerating the derived diary entries for a Viaggio. When the worker writes the enriched diary, it removes previously derived `MobilitySegment` and `SignificantPlace` rows for that trip and recreates them from the current core evidence, raw sensor evidence, and model output.

**Consequences**

Retrying a Celery task, recovering after worker failure, or deliberately reprocessing the same raw evidence with an updated model does not require diffing old and new segments. The raw evidence remains in object storage, while Postgres stores the latest derived diary representation.
