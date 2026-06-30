import 'package:diary/network/dto/trip_reload_dto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TripReloadDto', () {
    test('parses a direct reload response', () {
      final dto = TripReloadDto.fromJson({
        'ingestion_id': 10,
        'trip_id': 99,
        'core_status': 'COMPLETED',
        'raw_status': 'QUEUED',
        'gps_points': 120,
        'state_transitions': 2,
        'path_points': 118,
        'distance_meters': 3456.7,
        'map_available': true,
      });

      expect(dto.ingestionId, 10);
      expect(dto.tripId, 99);
      expect(dto.coreStatus, 'COMPLETED');
      expect(dto.rawStatus, 'QUEUED');
      expect(dto.gpsPoints, 120);
      expect(dto.stateTransitions, 2);
      expect(dto.pathPoints, 118);
      expect(dto.distanceMeters, 3456.7);
      expect(dto.mapAvailable, isTrue);
    });
  });
}
