# Privacy-Aware Diary

This document is a working plan for the Privacy dei dati di posizione component
of CAS 2026 Proposta 2. The plan assumes backend-side generation of
privacy-aware diary views: real evidence is stored for the private diary and HAR,
then reduced for export, sharing, and dashboard comparison.

## Source Requirements

The project brief asks the system to:

- let the mobile user configure the desired privacy level for sharing or
  exporting the diary;
- generate a privacy-aware diary with aggregated or perturbed data;
- compare the private detailed version with the shareable privacy-aware version;
- show on the web dashboard the real trace beside the anonymized or perturbed
  trace;
- study Privacy Perturbation as the distance between real and published
  positions;
- study Quality of Service as the loss of accuracy in diary reconstruction or
  statistics;
- visualize the trade-off between privacy and service quality.

The privacy requirement is interpreted as location privacy. The HAR pipeline
also consumes non-location sensor evidence, but the listed privacy techniques in
the brief and slides focus on position release: perturbation, spatial cloaking,
temporal aggregation, and dummy locations. In v1, the privacy-aware view protects
GPS-derived geometry and significant-place locations, not raw accelerometer or
gyroscope windows.

## Working Interpretation

The architecture is:

- the mobile app records the real trip evidence;
- the backend stores the real trip evidence and uses it for HAR, segmentation,
  significant-place detection, and the private diary;
- the privacy feature is applied when producing a shareable privacy-aware view;
- the mobile app can export the diary using the privacy-aware view, not the
  private detailed view;
- the web dashboard demonstrates the feature by comparing the private detailed
  view with the privacy-aware view.

This means the privacy feature protects the published or shareable diary view,
not the raw data from the backend itself.

## Domain Model

**Vista Privata del Diario**

The owner-facing diary view. It uses the best available data: real GPS track,
real movement segments, HAR labels, significant places, and precise statistics.

**Vista Privacy-Aware**

The shareable diary view. It is derived from the private diary by reducing,
perturbing, or aggregating location detail.

**Preferenza Privacy**

The user's current global choice for how precise the privacy-aware view should
be. It should not change the private diary or the HAR pipeline.

## Recommended Privacy Technique

Use spatial cloaking based on a grid.

The published position is not the exact GPS point. Each real point is assigned
to a spatial cell, and the privacy-aware geometry uses a representative point
for that cell, preferably the cell center.

The grid should be metric: cell sizes are expressed in meters, not by simply
dropping decimal digits from latitude and longitude. This keeps 150 m and 400 m
levels meaningful and repeatable for metrics and explanation.

The transformation is deterministic. The same real coordinate and the same
privacy level always produce the same published cell-center coordinate. This
keeps dashboard refreshes, exports, metrics, and tests stable.

The cloaking grid is not limited to Bologna or to a demo bounding box. It applies
to any valid GPS coordinate.

Suggested mapping:

- `precise`: no cloaking; the privacy-aware view equals the private geometry;
- `approximate`: 150 meter cells;
- `aggregated`: 400 meter cells, still rendered as a coarse privacy-aware
  trace.

This fits the project brief under cloaking spaziale. The implementation can be
described as grid quantization or truncation-based spatial cloaking.

For the first implementation, the privacy-aware transformation affects location
geometry only. Activity labels, segment intervals, and activity-duration
statistics are kept from the private diary. This keeps the first privacy slice
focused on the location-privacy requirement and makes the quality loss easier
to explain.

The same cloaking service should be applied to both the overall `Trip.path` and
each movement `MobilitySegment.path`. Transforming only one of them would leave
either the overall trace or the activity-colored segment paths precise.

The same transformation also applies to `SignificantPlace.center`. Significant
places are often the most sensitive locations in the diary because they can
reveal home, university, work, or other recurring personal places.

## Data Flow

The proposed flow is:

```text
real GPS + real sensor evidence
        -> HAR, segmentation, significant places
        -> private detailed diary
        -> privacy-aware transformation
        -> shareable diary view
```

The HAR pipeline should work on real data. Running HAR on cloaked data would
make activity recognition, stop detection, distance, speed, and significant
places worse before the diary has even been built.

HAR predictions are not recomputed for the privacy-aware view. The view reuses
the existing mobility segments and activity labels, then transforms only their
published geometry.

## Persistence Strategy

Persist:

- real trip evidence;
- real trip track;
- real mobility segments;
- real significant places;
- HAR labels on real mobility segments;
- user privacy preference.

Do not persist a second full copy of perturbed trips, perturbed GPS points, or
perturbed HAR predictions in the first implementation.

Generate the privacy-aware view on read. This is acceptable because grid
cloaking is deterministic for a given level and cell size.

## Dashboard Behavior

The web dashboard should make the trade-off visible:

- show the real track and the privacy-aware track;
- show the selected privacy level;
- show Privacy Perturbation metrics;
- show Quality of Service metrics;
- let the viewer compare precise, approximate, and aggregated outputs.

The existing web trip dashboard is the natural place to add this comparison,
because it already loads one trip, the track, mobility segments, and trip
statistics.

The dashboard should use the owner's saved privacy preference as the initial
selection, but it should also let the viewer preview all supported privacy
levels. This makes the privacy/quality trade-off visible during the demo without
requiring profile changes between screenshots or test runs.

For `approximate` and `aggregated`, the privacy-aware geometry is still a valid
GPS-like line. It is not another trip; it is the same trip represented through
cell-center coordinates. Consecutive duplicate cell centers can be collapsed so
the rendered line is readable. The dashboard may also draw translucent grid
cells to make the cloaked regions explicit.

Use a single comparison map with overlaid layers and a visibility toggle for:

- private detailed trace;
- privacy-aware trace;
- both traces together.

This makes the perturbation visually obvious. Side-by-side maps can be added
later, but v1 should optimize for direct visual comparison.

When a privacy-aware layer is active, the dashboard should optionally render the
cloaking cells as translucent polygons. The cell layer helps explain that the
published coordinate represents a region, not a random second trip.

For `approximate` and `aggregated`, the dashboard privacy-aware view should use
the same generic significant-stop wording as the mobile export. The private
comparison data may still show private labels when the private layer/details are
being inspected, but the privacy-aware representation itself should not expose
sensitive place labels.

## API Shape

Extend the existing web trip-dashboard response with a `privacy_aware` block
instead of creating a separate dashboard endpoint for the first implementation.
The dashboard needs private and privacy-aware data together to render the
comparison.

Conceptual response shape:

```text
owner
trip
track                  # private detailed track
diary                  # private detailed diary
privacy_aware
  level
  track                # cloaked track
  diary.segments       # same segments, cloaked movement paths
  metrics
    privacy_perturbation
    quality_of_service
```

A separate mobile export endpoint may still be useful later, but the first
dashboard implementation should extend the existing detail read model.

For mobile export, use a dedicated endpoint. The normal mobile diary endpoint
continues to return the private detailed diary, while the export endpoint returns
the privacy-aware representation controlled by the user's privacy preference.
Both endpoints can reuse the same internal cloaking service.

Conceptual mobile export endpoint:

```text
GET /api/mobility/trips/{trip_id}/privacy-export
```

## Mobile Export Behavior

The mobile app should expose an "export diary" action that uses the user's
privacy preference and requests or builds the privacy-aware diary view. The
export must not use the private detailed geometry unless the selected privacy
level is `precise`.

In v1, the export should be a preview screen, with optional copy or simple
text-share behavior. It can show a JSON or text representation of the diary with
the privacy-aware geometry and the existing segment labels/statistics. The
important behavior is that exporting follows the privacy level instead of
silently exporting the precise private diary.

The mobile export preview is text-only in v1. It does not need a privacy-aware
map; the map comparison belongs to the web dashboard.

The text export should include privacy-aware coordinates, clearly labeled as
approximated coordinates. This makes the export verifiable while avoiding the
impression that the values are the original GPS readings.

For `approximate` and `aggregated`, the export should not include sensitive
significant-place labels such as "home", "work", or "university". In these
privacy-aware exports, stops should use generic wording such as "significant
stop in approximated area". The `precise` export may include the private labels,
but it must be presented as unprotected.

Example export wording:

```text
08:15-08:35 walking
Privacy level: approximate
Cell size: 150 m
Privacy-aware path: 12 approximated points
08:35-12:10 significant stop in approximated area
```

The `precise` level is allowed for export, but it should be presented as an
unprotected export suitable only for trusted recipients. It remains useful as a
baseline for comparison with `approximate` and `aggregated`.

Cell sizes are fixed in v1. The user and dashboard choose the privacy level, not
the raw cell size. This keeps the demo and metrics repeatable.

## Metrics

**Privacy Perturbation**

For each real point and published point:

```text
distance(real_position, published_position)
```

Compute this over all original points paired with their published cell-center
positions. Consecutive duplicate cell centers may be collapsed for map
rendering, but not for the perturbation metric.

Useful summaries:

- mean perturbation distance;
- max perturbation distance;
- perturbation distance by privacy level.

**Quality of Service**

Primary v1 measure:

```text
abs(real_distance - privacy_aware_distance) / real_distance
```

This expresses the relative distance error introduced by the privacy-aware
geometry. It is easy to explain and works even when the trip has few or no
significant places.

Candidate future measures:

- number or percentage of significant places still recognizable after cloaking;
- difference between real and privacy-aware movement statistics;
- optionally, time-bucket or activity-statistics loss for aggregated mode.

## Open Questions

1. Should a future version support mobile-side perturbation for deployments where
   the backend is not trusted with precise location evidence?

## Decisions So Far

- The dashboard uses the saved user privacy preference as the initial selection
  but exposes a comparison control for all privacy levels.
- Privacy-aware diary views are generated backend-side from the private diary;
  mobile-side perturbation before upload is out of scope for this implementation.
- The first privacy-aware transformation changes only location geometry; HAR
  labels, segment intervals, and activity-duration statistics remain unchanged.
- `aggregated` remains a coarse privacy-aware trace in v1, not a separate
  zone-only visualization.
- The mobile app should include an export-diary action that uses the
  privacy-aware view controlled by the user's privacy preference.
- The first export implementation is a mobile preview, optionally with copy or
  simple text sharing, not a full PDF/file export.
- The first mobile export preview is text-only; it does not include a map.
- The text export includes approximated privacy-aware coordinates, clearly
  labeled as not being the original GPS readings.
- The text export omits sensitive significant-place labels and uses generic
  stop wording for `approximate` and `aggregated`.
- The `precise` privacy level is allowed for export, but is presented as
  unprotected and intended only for trusted recipients.
- Privacy cell sizes are fixed in v1: `approximate` uses 150 meter cells and
  `aggregated` uses 400 meter cells.
- The grid is metric and meter-based, not raw latitude/longitude decimal
  truncation.
- The privacy-aware transformation is deterministic for a given coordinate and
  privacy level.
- The cloaking transformation applies globally to any valid GPS coordinate, not
  only to Bologna demo traces.
- Privacy Perturbation is computed over all original points, even when duplicate
  published cell centers are collapsed for display.
- Privacy scope in v1 is location privacy: GPS-derived tracks, segment paths,
  and significant-place locations. Raw HAR sensor windows are not transformed.
- The v1 Quality of Service metric is relative distance error between the real
  track and the privacy-aware track.
- HAR is computed once from real evidence and is not recomputed from perturbed
  geometry.
- The cloaking transformation applies to both `Trip.path` and movement
  `MobilitySegment.path`.
- The cloaking transformation also applies to `SignificantPlace.center`.
- The first dashboard API extends the existing trip-dashboard response with a
  `privacy_aware` block instead of adding a separate dashboard endpoint.
- Mobile export uses a dedicated endpoint, separate from the private mobile
  diary endpoint.
- The dashboard comparison uses one map with overlaid private and privacy-aware
  traces plus layer toggles.
- The dashboard can show cloaking cells as an optional translucent layer when a
  privacy-aware trace is active.
- The dashboard privacy-aware representation masks sensitive significant-place
  labels for `approximate` and `aggregated`, matching mobile export behavior.

## First Implementation Slice

Build the smallest useful slice:

- backend service that derives a privacy-aware geometry from an existing track
  and segment paths;
- API response that includes private and privacy-aware geometries for one trip;
- dashboard comparison between real and privacy-aware trace;
- mobile export action that uses the privacy-aware diary representation;
- metric cards or simple charts for Privacy Perturbation and one Quality of
  Service measure.

The export can stay lightweight in v1. The dashboard comparison remains the main
visual proof of the privacy technique, while the export action gives concrete
product meaning to "shareable diary."
