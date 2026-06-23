# Trip Detail Uses Foreground SSE For Diary Enrichment

## Status

Accepted

## Context

After Core Ingestion completes, the mobile app receives a `trip_id` and can show
the Dettaglio Viaggio before Raw Sensor Ingestion/HAR has finished enriching the
diary.

The previous UI discovery mechanism used controlled polling: periodically fetch
the diary read model until it becomes processed. For the demo flow, the app is
expected to remain open while the user watches the Dettaglio Viaggio.

## Decision

Use a foreground Server-Sent Events stream for one Viaggio while its Dettaglio
Viaggio is open and the diary is not yet enriched.

The stream endpoint is scoped to one trip:

```http
GET /api/mobility/trips/{trip_id}/events
Accept: text/event-stream
```

When the backend emits `diary_enriched`, the mobile app refetches
`GET /api/mobility/trips/{trip_id}/diary`. The event is only a wake-up signal;
the diary read model remains the source of truth.

## Alternatives Considered

- Keep periodic polling in the Trip detail UI.
- Use WebSockets.
- Use native push notifications through APNs/Firebase.
- Open a stream from the SyncQueue immediately after Core Ingestion completes.

## Consequences

The Dettaglio Viaggio can update promptly when HAR completes without continuous
polling while the page is visible. The stream lifecycle is tied to the page:
open it when the user is watching a pending diary, close it when the page closes
or the diary becomes enriched.

This does not support app-closed delivery. If the app is reopened later, it must
still refetch the diary/read model normally.
