import assert from 'node:assert/strict';
import test from 'node:test';
import {
  activityFilterOptions,
  filterSegments,
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

test('summarizeTrip can summarize the currently visible subset', () => {
  const visible = filterSegments(segments, { activities: ['BIKING'] });
  const stats = summarizeTrip(trip, visible, { durationMode: 'segments' });

  assert.equal(stats.totalDurationSeconds, 1800);
  assert.equal(stats.movementSeconds, 1800);
  assert.equal(stats.stoppedSeconds, 0);
  assert.equal(stats.movementDistanceMeters, 1500);
  assert.deepEqual(stats.activitySplit.map((item) => item.label), ['Bici']);
});

function segment(kind, activity_label, start_timestamp, end_timestamp, distance_meters) {
  return {
    kind,
    start_timestamp,
    end_timestamp,
    activity_label,
    distance_meters,
    path_geojson: null,
  };
}
