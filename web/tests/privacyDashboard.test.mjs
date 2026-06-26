import assert from 'node:assert/strict';
import test from 'node:test';
import {
  isProtectedLevel,
  privacyLevelLabel,
  privacyLevelOptions,
  privacyMetricCards,
} from '../.tmp-tests/src/utils/privacyDashboard.js';

const metrics = {
  privacy_perturbation: { mean_meters: 84, max_meters: 132, sample_count: 12 },
  quality_of_service: {
    relative_distance_error: 0.123,
    private_distance_meters: 2000,
    privacy_aware_distance_meters: 1850,
  },
};

test('privacyLevelOptions exposes precise/approximate/aggregated with cell sizes', () => {
  assert.deepEqual(
    privacyLevelOptions.map((option) => option.value),
    ['precise', 'approximate', 'aggregated'],
  );
  assert.equal(privacyLevelLabel('approximate'), 'Approssimata');
  assert.equal(
    privacyLevelOptions.find((option) => option.value === 'approximate')?.cellLabel,
    'Celle 150 m',
  );
});

test('isProtectedLevel marks only precise as unprotected', () => {
  assert.equal(isProtectedLevel('precise'), false);
  assert.equal(isProtectedLevel('approximate'), true);
  assert.equal(isProtectedLevel('aggregated'), true);
});

test('privacyMetricCards summarizes perturbation and quality loss', () => {
  const cards = privacyMetricCards(metrics, 'approximate');
  assert.deepEqual(cards.map((card) => card.key), [
    'perturbation-mean',
    'perturbation-max',
    'quality-loss',
  ]);
  assert.equal(cards[0].value, '84 m');
  assert.equal(cards[0].hint, '12 punti');
  assert.equal(cards[2].value, '12.3%');
});
