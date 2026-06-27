# Significant Place Mining Runs After Diary Enrichment

Status: accepted

Riconoscimento dei Luoghi Significativi should run as the final asynchronous step after one Viaggio has finished diary enrichment, so the system can mine cross-Viaggio visits from the latest processed evidence without making the mobile app trigger a separate flow. We considered computing candidate places only when the user opens a dedicated screen, but keeping the mining step in the backend pipeline makes the diary, the candidate list, and later manual review all converge on the same up-to-date derived state.
