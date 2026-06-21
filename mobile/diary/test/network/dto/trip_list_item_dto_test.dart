import 'package:diary/network/dto/trip_list_item_dto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TripListItemDto', () {
    test('parses a complete trip with track and distance', () {
      final dto = TripListItemDto.fromJson({
        'id': 7,
        'started_at': '2026-06-12T10:00:00Z',
        'ended_at': '2026-06-12T10:35:00Z',
        'status': 'PROCESSED',
        'distance_meters': 1234.5,
        'has_track': true,
      });

      expect(dto.id, 7);
      expect(dto.startedAt.isUtc, isTrue);
      expect(dto.endedAt, isNotNull);
      expect(dto.status, 'PROCESSED');
      expect(dto.distanceMeters, 1234.5);
      expect(dto.hasTrack, isTrue);
    });

    test('handles missing ended_at, distance and track flag', () {
      final dto = TripListItemDto.fromJson({
        'id': 8,
        'started_at': '2026-06-12T10:00:00Z',
        'ended_at': null,
        'status': 'CLOSED',
        'distance_meters': null,
        'has_track': false,
      });

      expect(dto.endedAt, isNull);
      expect(dto.distanceMeters, isNull);
      expect(dto.hasTrack, isFalse);
    });
  });
}
