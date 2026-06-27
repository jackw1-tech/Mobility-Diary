# Significant Place Discovery Comes Only From Raw GPS

Status: accepted

The first implementation of significant-place recognition should discover places only from raw `GpsPoint` permanence detection, not from the existing trip-scoped `SignificantPlace` derivation in the diary pipeline. We considered fusing diary stop places with raw GPS as peer discovery inputs, but keeping raw GPS as the only discovery source gives one clear algorithmic path, avoids duplicating place semantics at two levels, and makes the new feature easier to reason about while the old trip-scoped place logic is being phased out.
