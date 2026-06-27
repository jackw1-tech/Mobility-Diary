# Significant Place Mining Does Not Rewrite Diary Segmentation

Status: accepted

Riconoscimento dei Luoghi Significativi may use both raw `GpsPoint` evidence and already derived stop intervals as peer signals for place recognition, but it must not create, split, or correct `MobilitySegment` rows in the Diario della Mobilita. We considered letting strong place evidence rewrite stop segmentation, but keeping segmentation and place recognition separate preserves a stable diary timeline while still allowing richer stop descriptions and a dedicated place-review experience.
