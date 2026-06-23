import 'package:diary/network/dto/trip_track_dto.dart';
import 'package:diary/ui/pages/trip_diary_presenter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TripStats', () {
    test('calculates duration, movement, stops, distance and activity split',
        () {
      final start = DateTime.parse('2026-06-12T10:00:00Z');
      final stats = TripStats.fromSegments([
        _segment(
          kind: 'MOVE',
          activity: 'WALKING',
          start: start,
          end: start.add(const Duration(minutes: 10)),
          distance: 700,
        ),
        _segment(
          kind: 'STOP',
          activity: 'IDLE',
          start: start.add(const Duration(minutes: 10)),
          end: start.add(const Duration(minutes: 25)),
          place: _place(1),
        ),
        _segment(
          kind: 'MOVE',
          activity: 'BIKING',
          start: start.add(const Duration(minutes: 25)),
          end: start.add(const Duration(minutes: 45)),
          distance: 3000,
        ),
      ]);

      expect(stats.duration, const Duration(minutes: 45));
      expect(stats.moving, const Duration(minutes: 30));
      expect(stats.stopped, const Duration(minutes: 15));
      expect(stats.distanceMeters, 3700);
      expect(stats.places, 1);
      expect(stats.activities.map((a) => a.label), ['BIKING', 'WALKING']);
    });
  });

  group('diary presentation', () {
    test('maps labels and stop titles', () {
      expect(activityLabelText('WALKING'), 'A piedi');
      expect(activityLabelText('MOVING_VEHICLE'), 'Veicolo');
      expect(segmentTitle(_segment(kind: 'STOP', activity: 'IDLE')),
          'Sosta rilevata');
      expect(
        segmentTitle(
            _segment(kind: 'STOP', activity: 'IDLE', place: _place(7))),
        'Casa',
      );
    });
  });
}

TripDiarySegmentDto _segment({
  required String kind,
  required String activity,
  DateTime? start,
  DateTime? end,
  double distance = 0,
  TripDiaryPlaceDto? place,
}) {
  final from = start ?? DateTime.parse('2026-06-12T10:00:00Z');
  return TripDiarySegmentDto(
    kind: kind,
    startTimestamp: from,
    endTimestamp: end ?? from.add(const Duration(minutes: 5)),
    activityLabel: activity,
    distanceMeters: distance,
    pathGeojson: null,
    place: place,
  );
}

TripDiaryPlaceDto _place(int id) {
  return TripDiaryPlaceDto(
    id: id,
    latitude: 45.0,
    longitude: 9.0,
    radiusMeters: 20,
    dwellSeconds: 600,
    label: 'Casa',
  );
}
