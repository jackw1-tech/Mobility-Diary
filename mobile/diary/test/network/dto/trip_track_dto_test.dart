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

    test('parses segmented diary with movement geometry and stop place', () {
      final dto = TripDiaryDto.fromJson({
        'trip_id': 7,
        'status': 'PROCESSED',
        'processed': true,
        'segments': [
          {
            'kind': 'MOVE',
            'start_timestamp': '2026-06-12T10:00:00Z',
            'end_timestamp': '2026-06-12T10:05:00Z',
            'activity_label': 'BIKING',
            'distance_meters': 1234.5,
            'path_geojson': {
              'type': 'LineString',
              'coordinates': [
                [9.10, 45.46],
                [9.20, 45.47],
              ],
            },
            'place': null,
          },
          {
            'kind': 'STOP',
            'start_timestamp': '2026-06-12T10:05:00Z',
            'end_timestamp': '2026-06-12T10:20:00Z',
            'activity_label': 'IDLE',
            'distance_meters': 0,
            'path_geojson': null,
            'place': {
              'id': 3,
              'lat': 45.47,
              'lon': 9.20,
              'radius_meters': 30,
              'dwell_seconds': 900,
              'label': 'universita',
            },
          },
        ],
        'places': [],
      });

      expect(dto.processed, isTrue);
      expect(dto.drawableSegments, hasLength(1));
      expect(dto.movementDistanceMeters, 1234.5);
      final move = dto.drawableSegments.single;
      expect(move.points.first.latitude, 45.46);
      expect(move.points.first.longitude, 9.10);
      expect(move.points.last.latitude, 45.47);
      expect(move.points.last.longitude, 9.20);
      final stop = dto.segments.last;
      expect(stop.points, isEmpty);
      expect(stop.place!.label, 'universita');
    });
  });
}
