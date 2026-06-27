# Significant Place Mining Is Serialized Per User

Status: accepted

The first implementation of Riconoscimento dei Luoghi Significativi should allow only one mining job at a time for each Proprietario del Viaggio. We considered letting multiple trip-triggered recomputations run concurrently, but serializing per user avoids race conditions while recomputing user-scoped clusters, candidate states, and manual-review outcomes from the full trip history.
