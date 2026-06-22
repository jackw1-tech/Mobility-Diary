# Frontend Discovers HAR Enrichment By Polling A Segmented Read Model

Status: accepted

The frontend should discover final HAR enrichment through controlled polling, then refetch a segmented diary read model. The first implementation should not depend on WebSockets, Server-Sent Events, or push notifications; those may be added later only as wake-up hints that tell the client to refetch backend state.

**Considered Options**

- Push completion events to the frontend and let the event drive the UI.
- Poll ingestion/read-model state and render the latest persisted diary.
- Poll only the raw track endpoint and let the frontend derive activity segments locally.

**Consequences**

The backend remains the source of truth for Segmenti di Mobilita, activity labels, stop/place intervals, and segment geometry. Mobile and web clients poll status until Raw Sensor Ingestion reaches `COMPLETED`, then request the segmented diary/map read model and switch from a plain Traiettoria del Viaggio to the enriched segment view.
