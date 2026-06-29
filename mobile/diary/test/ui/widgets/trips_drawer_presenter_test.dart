import 'package:diary/network/dto/trip_list_item_dto.dart';
import 'package:diary/ui/widgets/trips_drawer_presenter.dart';
import 'package:flutter_test/flutter_test.dart';

TripListItemDto _trip(
  int id,
  DateTime startedAt, {
  bool hasTrack = true,
}) {
  return TripListItemDto(
    id: id,
    startedAt: startedAt,
    endedAt: startedAt.add(const Duration(minutes: 20)),
    status: 'COMPLETED',
    distanceMeters: 1200,
    hasTrack: hasTrack,
  );
}

void main() {
  group('groupTrackTripsByLocalDay', () {
    test('groups only trips with a track by local day', () {
      final trips = [
        _trip(1, DateTime(2026, 6, 29, 8)),
        _trip(2, DateTime(2026, 6, 29, 17), hasTrack: false),
        _trip(3, DateTime(2026, 6, 28, 10)),
      ];

      final groups = groupTrackTripsByLocalDay(trips);

      expect(groups, hasLength(2));
      expect(groups.first.day, DateTime(2026, 6, 29));
      expect(groups.first.trips.map((trip) => trip.id), [1]);
      expect(groups.last.day, DateTime(2026, 6, 28));
      expect(groups.last.trips.map((trip) => trip.id), [3]);
    });

    test('filters out days below the requested minimum trip count', () {
      final trips = [
        _trip(1, DateTime(2026, 6, 29, 8)),
        _trip(2, DateTime(2026, 6, 29, 12)),
        _trip(3, DateTime(2026, 6, 28, 10)),
      ];

      final groups = groupTrackTripsByLocalDay(trips, minTrips: 2);

      expect(groups, hasLength(1));
      expect(groups.single.day, DateTime(2026, 6, 29));
      expect(groups.single.trips.map((trip) => trip.id), [1, 2]);
    });
  });

  group('sameLocalDayTrackTrips', () {
    test('returns tracked trips on the selected trip local day ordered by time',
        () {
      final trips = [
        _trip(1, DateTime(2026, 6, 29, 18)),
        _trip(2, DateTime(2026, 6, 29, 8)),
        _trip(3, DateTime(2026, 6, 29, 9), hasTrack: false),
        _trip(4, DateTime(2026, 6, 28, 10)),
      ];

      expect(sameLocalDayTrackTrips(trips, 1).map((trip) => trip.id), [2, 1]);
      expect(sameLocalDayTrackTrips(trips, 99), isEmpty);
    });
  });
}
