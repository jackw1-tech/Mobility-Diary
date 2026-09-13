import 'package:diary/model/entities/analytics/analytics.dart';
import 'package:diary/model/entities/trips/trip_enums.dart';
import 'package:diary/model/entities/trips/trip_list_item.dart';
import 'package:diary/model/entities/trips/trip_track.dart';
import 'package:diary/ui/pages/analytics_presenter.dart';
import 'package:diary/ui/pages/trip_diary_presenter.dart';
import 'package:diary/ui/widgets/trips_drawer_presenter.dart';
import 'package:flutter_test/flutter_test.dart';

TripDiarySegment segment({
  required TripDiarySegmentKind kind,
  required DateTime start,
  required DateTime end,
  MobilityActivity activity = MobilityActivity.walking,
  double distanceMeters = 0,
  TripDiaryPlace? place,
}) {
  return TripDiarySegment(
    kind: kind,
    startTimestamp: start,
    endTimestamp: end,
    activity: activity,
    distanceMeters: distanceMeters,
    pathGeojson: null,
    place: place,
  );
}

TripListItem trip(int id, DateTime startedAt, {bool hasTrack = true}) {
  return TripListItem(
    id: id,
    startedAt: startedAt,
    endedAt: startedAt.add(const Duration(minutes: 10)),
    status: TripStatus.processed,
    distanceMeters: 500,
    hasTrack: hasTrack,
  );
}

void main() {
  test('trip stats aggregate ordered movement and stop segments', () {
    final start = DateTime.utc(2026, 8, 30, 10);
    final stats = TripStats.fromSegments([
      segment(
        kind: TripDiarySegmentKind.stop,
        start: start.add(const Duration(minutes: 10)),
        end: start.add(const Duration(minutes: 15)),
        activity: MobilityActivity.idle,
      ),
      segment(
        kind: TripDiarySegmentKind.move,
        start: start,
        end: start.add(const Duration(minutes: 10)),
        distanceMeters: 800,
      ),
    ]);

    expect(stats.duration, const Duration(minutes: 15));
    expect(stats.moving, const Duration(minutes: 10));
    expect(stats.stopped, const Duration(minutes: 5));
    expect(stats.distanceMeters, 800);
    expect(stats.stopCount, 1);
    expect(stopStatsText(stats), '1 sosta · 5 min');
  });

  test('negative segment durations never reduce diary totals', () {
    final start = DateTime.utc(2026, 8, 30, 10);
    final stats = TripStats.fromSegments([
      segment(
        kind: TripDiarySegmentKind.move,
        start: start,
        end: start.subtract(const Duration(minutes: 1)),
        distanceMeters: 25,
      ),
    ]);

    expect(stats.moving, Duration.zero);
    expect(stats.activities.single.duration, Duration.zero);
  });

  test(
    'groups only drawable trips by local day and orders recent days first',
    () {
      final groups = groupTrackTripsByLocalDay([
        trip(1, DateTime(2026, 8, 29, 8)),
        trip(2, DateTime(2026, 8, 30, 9)),
        trip(3, DateTime(2026, 8, 30, 10), hasTrack: false),
      ]);

      expect(groups.length, 2);
      expect(groups.first.trips.map((item) => item.id), [2]);
      expect(groups.last.trips.map((item) => item.id), [1]);
    },
  );

  test('same-day comparison returns drawable trips in chronological order', () {
    final trips = [
      trip(2, DateTime(2026, 8, 30, 10)),
      trip(1, DateTime(2026, 8, 30, 8)),
      trip(3, DateTime(2026, 8, 31, 8)),
    ];

    expect(sameLocalDayTrackTrips(trips, 2).map((item) => item.id), [1, 2]);
    expect(sameLocalDayTrackTrips(trips, 999), isEmpty);
  });

  test('analytics window shows the latest seven buckets by default', () {
    final buckets = List.generate(
      10,
      (index) => AnalyticsBucket(label: 'day-$index', categories: const []),
    );
    final start = analyticsDefaultWindowStart(buckets.length);

    expect(start, 3);
    expect(analyticsNeedsWindowSlider(buckets.length), isTrue);
    expect(analyticsWindow(buckets, start).map((bucket) => bucket.label), [
      'day-3',
      'day-4',
      'day-5',
      'day-6',
      'day-7',
      'day-8',
      'day-9',
    ]);
  });

  test('analytics totals exclude stopped time from movement total', () {
    final totals = calculateAnalyticsTotals([
      const AnalyticsBucket(
        label: '2026-08-30',
        categories: [
          AnalyticsCategorySlice(
            category: 'IDLE',
            seconds: 300,
            distanceMeters: 0,
          ),
          AnalyticsCategorySlice(
            category: 'WALKING',
            seconds: 600,
            distanceMeters: 800,
          ),
          AnalyticsCategorySlice(
            category: 'BIKING',
            seconds: 120,
            distanceMeters: 500,
          ),
        ],
      ),
    ]);

    expect(totals.movementTime, const Duration(minutes: 12));
    expect(totals.totalDistanceMeters, 1300);
  });
}
