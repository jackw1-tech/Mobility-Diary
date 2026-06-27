# Significant Place Mining Recomputes Per-User History

Status: accepted

After the final asynchronous enrichment of a Viaggio, the first implementation of Riconoscimento dei Luoghi Significativi should recompute places against the full history of that Proprietario del Viaggio instead of trying to update clusters incrementally. We considered incremental updates from only the newest trip, but full per-user recomputation is simpler to reason about, avoids cluster-drift bugs while the feature is still being tuned, and stays acceptable because the scope is user-scoped rather than global.
