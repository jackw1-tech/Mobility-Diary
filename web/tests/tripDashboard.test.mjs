import assert from 'node:assert/strict';
import test from 'node:test';
import {
  activityFilterOptions,
  filterSegments,
  presentableSegments,
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

test('presentableSegments collapses idle plus stop plus idle into one stop', () => {
  const projected = presentableSegments([
    segment('MOVE', 'IDLE', '2026-06-24T08:10:00.000Z', '2026-06-24T08:12:00.000Z', 20),
    segment('STOP', 'IDLE', '2026-06-24T08:12:00.000Z', '2026-06-24T08:20:00.000Z', 0),
    segment('MOVE', 'IDLE', '2026-06-24T08:20:00.000Z', '2026-06-24T08:23:00.000Z', 15),
  ]);

  assert.equal(projected.length, 1);
  assert.equal(projected[0].kind, 'STOP');
  assert.equal(projected[0].activity_label, 'IDLE');
  assert.equal(projected[0].distance_meters, 0);
  assert.equal(projected[0].path_geojson, null);
  assert.equal(projected[0].start_timestamp, '2026-06-24T08:10:00.000Z');
  assert.equal(projected[0].end_timestamp, '2026-06-24T08:23:00.000Z');
});

test('summarizeTrip treats idle plus stop plus idle as one stop', () => {
  const stats = summarizeTrip(trip, [
    segment('MOVE', 'WALKING', '2026-06-24T08:00:00.000Z', '2026-06-24T08:10:00.000Z', 500),
    segment('MOVE', 'IDLE', '2026-06-24T08:10:00.000Z', '2026-06-24T08:12:00.000Z', 20),
    segment('STOP', 'IDLE', '2026-06-24T08:12:00.000Z', '2026-06-24T08:20:00.000Z', 0),
    segment('MOVE', 'IDLE', '2026-06-24T08:20:00.000Z', '2026-06-24T08:23:00.000Z', 15),
    segment('MOVE', 'BIKING', '2026-06-24T08:23:00.000Z', '2026-06-24T09:00:00.000Z', 1500),
  ]);

  assert.equal(stats.totalDurationSeconds, 3600);
  assert.equal(stats.movementSeconds, 2820);
  assert.equal(stats.stoppedSeconds, 780);
  assert.equal(stats.movementDistanceMeters, 2000);
  assert.deepEqual(stats.activitySplit.map((item) => item.label), ['Bici', 'Camminata']);
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
