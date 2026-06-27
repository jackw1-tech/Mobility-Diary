# Diary Applies Significant Place Labels At Read Time

Status: accepted

Manual labels and confirmed significant-place metadata should enrich the Diario della Mobilita as a read-time overlay instead of rewriting persisted `MobilitySegment` rows. We considered rebuilding historical diary read models whenever a place is labeled or rejected, but applying place names and neutral place wording at response time keeps the diary immediately up to date while preserving the existing asynchronous segmentation pipeline as the stable source of trip structure.
