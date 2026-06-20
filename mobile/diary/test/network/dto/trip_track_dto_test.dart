import 'package:diary/network/dto/trip_track_dto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TripTrackDto', () {
    test('parses GeoJSON LineString preserving lon/lat order', () {
      final dto = TripTrackDto.fromJson({
        'trip_id': 7,
        'point_count': 2,
        'distance_meters': 1234.5,
        'geojson': {
          'type': 'LineString',
          'coordinates': [
            [9.10, 45.46],
            [9.20, 45.47],
          ],
        },
      });

      expect(dto.tripId, 7);
      expect(dto.distanceMeters, 1234.5);
      expect(dto.points, hasLength(2));
      expect(dto.points.first.latitude, 45.46);
      expect(dto.points.first.longitude, 9.10);
      expect(dto.points.last.latitude, 45.47);
      expect(dto.points.last.longitude, 9.20);
    });

    test('returns empty points when GeoJSON is null', () {
      final dto = TripTrackDto.fromJson({
        'trip_id': 7,
        'point_count': 1,
        'distance_meters': 0,
        'geojson': null,
      });

      expect(dto.points, isEmpty);
    });
  });
}
