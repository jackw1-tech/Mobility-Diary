import assert from 'node:assert/strict';
import test from 'node:test';
import {
  activityFilterOptions,
  filterSegments,
  orderedSegments,
  placeFilterOptions,
  stopLabel,
  summarizeTrip,
} from '../.tmp-tests/src/utils/tripDashboard.js';

const trip = {
  id: 7,
  started_at: '2026-06-24T08:00:00.000Z',
  ended_at: '2026-06-24T09:00:00.000Z',
  status: 'PROCESSED',
  distance_meters: 2000,
  processed: true,
};

const segments = [
  segment('MOVE', 'WALKING', '2026-06-24T08:00:00.000Z', '2026-06-24T08:10:00.000Z', 500),
  segment('STOP', 'IDLE', '2026-06-24T08:10:00.000Z', '2026-06-24T08:30:00.000Z', 0),
  segment('MOVE', 'BIKING', '2026-06-24T08:30:00.000Z', '2026-06-24T09:00:00.000Z', 1500),
];

test('activityFilterOptions returns labels present in the open trip', () => {
  assert.deepEqual(
    activityFilterOptions(segments).map((option) => option.label),
    ['Camminata', 'Sosta', 'Bici'],
  );
});

test('placeFilterOptions returns places present in the filtered diary', () => {
  const placeSegments = [
    segment('STOP', 'IDLE', '2026-06-24T08:10:00.000Z', '2026-06-24T08:20:00.000Z', 0, {
      label: 'casa',
      center_geojson: { type: 'Point', coordinates: [9.2, 45.47] },
      radius_meters: 35,
    }),
    segment('STOP', 'IDLE', '2026-06-24T08:30:00.000Z', '2026-06-24T08:40:00.000Z', 0, {
      label: 'lavoro',
      center_geojson: { type: 'Point', coordinates: [9.3, 45.48] },
      radius_meters: 35,
    }),
  ];

  assert.deepEqual(placeFilterOptions(placeSegments).map((option) => option.label), [
    'casa',
    'lavoro',
  ]);
});

test('filterSegments filters by activity and overlapping time interval', () => {
  assert.deepEqual(
    filterSegments(segments, { activities: ['BIKING'] }).map((item) => item.activity_label),
    ['BIKING'],
  );

  assert.deepEqual(
    filterSegments(segments, {
      from: '2026-06-24T08:05:00.000Z',
      to: '2026-06-24T08:20:00.000Z',
    }).map((item) => item.activity_label),
    ['WALKING', 'IDLE'],
  );
});

test('filterSegments filters by significant place label', () => {
  const placeSegments = [
    segment('MOVE', 'WALKING', '2026-06-24T08:00:00.000Z', '2026-06-24T08:10:00.000Z', 500),
    segment('STOP', 'IDLE', '2026-06-24T08:10:00.000Z', '2026-06-24T08:20:00.000Z', 0, {
      label: 'casa',
      center_geojson: { type: 'Point', coordinates: [9.2, 45.47] },
      radius_meters: 35,
    }),
    segment('STOP', 'IDLE', '2026-06-24T08:30:00.000Z', '2026-06-24T08:40:00.000Z', 0, {
      label: 'lavoro',
      center_geojson: { type: 'Point', coordinates: [9.3, 45.48] },
      radius_meters: 35,
    }),
  ];

  assert.deepEqual(
    filterSegments(placeSegments, { place: 'casa' }).map((item) => item.place?.label),
    ['casa'],
  );
});

test('filterSegments clips segments to the selected active time window', () => {
  const visible = filterSegments(segments, {
    from: '2026-06-24T08:05:00.000Z',
    to: '2026-06-24T08:20:00.000Z',
  });

  assert.deepEqual(visible.map((item) => item.start_timestamp), [
    '2026-06-24T08:05:00.000Z',
    '2026-06-24T08:10:00.000Z',
  ]);
  assert.deepEqual(visible.map((item) => item.end_timestamp), [
    '2026-06-24T08:10:00.000Z',
    '2026-06-24T08:20:00.000Z',
  ]);
  assert.equal(visible[0].distance_meters, 250);

  const stats = summarizeTrip(trip, visible, { durationMode: 'segments' });
  assert.equal(stats.totalDurationSeconds, 900);
  assert.equal(stats.movementSeconds, 300);
  assert.equal(stats.stoppedSeconds, 600);
});

test('filterSegments clips move paths with the selected time window', () => {
  const [visible] = filterSegments([
    {
      ...segment('MOVE', 'WALKING', '2026-06-24T08:00:00.000Z', '2026-06-24T08:40:00.000Z', 400),
      path_geojson: {
        type: 'LineString',
        coordinates: [
          [0, 45],
          [1, 45],
          [2, 45],
          [3, 45],
          [4, 45],
        ],
      },
    },
  ], {
    from: '2026-06-24T08:10:00.000Z',
    to: '2026-06-24T08:30:00.000Z',
  });

  assert.deepEqual(visible.path_geojson.coordinates, [
    [1, 45],
    [2, 45],
    [3, 45],
  ]);
});

test('summarizeTrip can summarize the currently visible subset', () => {
  const visible = filterSegments(segments, { activities: ['BIKING'] });
  const stats = summarizeTrip(trip, visible, { durationMode: 'segments' });

  assert.equal(stats.totalDurationSeconds, 1800);
  assert.equal(stats.movementSeconds, 1800);
  assert.equal(stats.stoppedSeconds, 0);
  assert.equal(stats.stopCount, 0);
  assert.equal(stats.movementDistanceMeters, 1500);
  assert.deepEqual(stats.activitySplit.map((item) => item.label), ['Bici']);
});

test('orderedSegments keeps backend-projected stop rows unchanged', () => {
  const projected = orderedSegments([
    segment('STOP', 'IDLE', '2026-06-24T08:12:00.000Z', '2026-06-24T08:20:00.000Z', 0),
    segment('STOP', 'IDLE', '2026-06-24T08:10:00.000Z', '2026-06-24T08:12:00.000Z', 0),
  ]);

  assert.equal(projected.length, 2);
  assert.equal(projected[0].kind, 'STOP');
  assert.equal(projected[0].start_timestamp, '2026-06-24T08:10:00.000Z');
  assert.equal(projected[1].start_timestamp, '2026-06-24T08:12:00.000Z');
});

test('summarizeTrip trusts backend stop counts without local merging', () => {
  const stats = summarizeTrip(trip, [
    segment('MOVE', 'WALKING', '2026-06-24T08:00:00.000Z', '2026-06-24T08:10:00.000Z', 500),
    segment('STOP', 'IDLE', '2026-06-24T08:10:00.000Z', '2026-06-24T08:12:00.000Z', 0),
    segment('STOP', 'IDLE', '2026-06-24T08:13:00.000Z', '2026-06-24T08:20:00.000Z', 0),
    segment('MOVE', 'BIKING', '2026-06-24T08:20:00.000Z', '2026-06-24T09:00:00.000Z', 1500),
  ]);

  assert.equal(stats.totalDurationSeconds, 3600);
  assert.equal(stats.movementSeconds, 3000);
  assert.equal(stats.stoppedSeconds, 540);
  assert.equal(stats.stopCount, 2);
  assert.equal(stats.movementDistanceMeters, 2000);
  assert.deepEqual(stats.activitySplit.map((item) => item.label), ['Bici', 'Camminata']);
});

test('summarizeTrip matches one merged backend stop between two moves', () => {
  const stats = summarizeTrip(
    {
      ...trip,
      ended_at: '2026-06-24T08:20:00.000Z',
    },
    [
      segment('MOVE', 'BIKING', '2026-06-24T08:00:00.000Z', '2026-06-24T08:05:00.000Z', 600),
      segment('STOP', 'IDLE', '2026-06-24T08:05:00.000Z', '2026-06-24T08:15:00.000Z', 0, {
        label: 'casa',
        center_geojson: { type: 'Point', coordinates: [9.2, 45.47] },
        radius_meters: 35,
      }),
      segment('MOVE', 'WALKING', '2026-06-24T08:15:00.000Z', '2026-06-24T08:20:00.000Z', 500),
    ],
  );

  assert.equal(stats.totalDurationSeconds, 1200);
  assert.equal(stats.movementSeconds, 600);
  assert.equal(stats.stoppedSeconds, 600);
  assert.equal(stats.stopCount, 1);
  assert.equal(stats.movementDistanceMeters, 1100);
  assert.deepEqual(stats.activitySplit.map((item) => item.label), ['Bici', 'Camminata']);
});

test('stopLabel prefers the backend-provided place label', () => {
  assert.equal(
    stopLabel(segment('STOP', 'IDLE', '2026-06-24T08:10:00.000Z', '2026-06-24T08:20:00.000Z', 0, {
      label: 'casa',
      center_geojson: { type: 'Point', coordinates: [9.2, 45.47] },
      radius_meters: 35,
    })),
    'casa',
  );
  assert.equal(
    stopLabel(segment('STOP', 'IDLE', '2026-06-24T08:10:00.000Z', '2026-06-24T08:20:00.000Z', 0)),
    'Sosta rilevata',
  );
});

function segment(kind, activity_label, start_timestamp, end_timestamp, distance_meters, place = null) {
  return {
    kind,
    start_timestamp,
    end_timestamp,
    activity_label,
    distance_meters,
    path_geojson: null,
    place,
  };
}
