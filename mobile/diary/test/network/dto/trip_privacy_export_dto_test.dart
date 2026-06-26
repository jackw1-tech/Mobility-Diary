import 'package:diary/features/privacy/domain/privacy_level.dart';
import 'package:diary/network/dto/trip_privacy_export_dto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TripPrivacyExportDto', () {
    test('parses a precise unprotected export with real coordinates', () {
      final dto = TripPrivacyExportDto.fromJson(const {
        'trip_id': 3,
        'level': 'precise',
        'protected': false,
        'approximated_coordinates': false,
        'cell_size_meters': null,
        'text': 'Privacy level: precise',
        'segments': [
          {
            'kind': 'MOVE',
            'start_label': '08:15',
            'end_label': '08:35',
            'activity_label': 'WALKING',
            'title': 'walking',
            'point_count': 2,
            'coordinates': [
              [9.1, 45.46],
              [9.2, 45.47],
            ],
          },
          {
            'kind': 'STOP',
            'start_label': '08:35',
            'end_label': '08:55',
            'activity_label': 'IDLE',
            'title': 'universita',
            'point_count': 0,
            'coordinates': <List<double>>[],
          },
        ],
      });

      expect(dto.level, PrivacyLevel.precise);
      expect(dto.isProtected, isFalse);
      expect(dto.approximatedCoordinates, isFalse);
      expect(dto.cellSizeMeters, isNull);
      final move = dto.segments.first;
      expect(move.coordinates, [
        [9.1, 45.46],
        [9.2, 45.47],
      ]);
      expect(dto.segments.last.title, 'universita');
    });

    test('parses an approximate protected export with masked stop wording', () {
      final dto = TripPrivacyExportDto.fromJson(const {
        'trip_id': 3,
        'level': 'approximate',
        'protected': true,
        'approximated_coordinates': true,
        'cell_size_meters': 150,
        'text': 'Privacy level: approximate',
        'segments': [
          {
            'kind': 'STOP',
            'start_label': '08:35',
            'end_label': '08:55',
            'activity_label': 'IDLE',
            'title': 'Sosta significativa in area approssimata',
            'point_count': 0,
            'coordinates': <List<double>>[],
          },
        ],
      });

      expect(dto.level, PrivacyLevel.approximate);
      expect(dto.isProtected, isTrue);
      expect(dto.approximatedCoordinates, isTrue);
      expect(dto.cellSizeMeters, 150);
      expect(dto.segments.single.title,
          'Sosta significativa in area approssimata');
    });
  });
}
