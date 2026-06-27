import 'package:diary/network/dto/place_review_dto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlaceReviewDto', () {
    test('parses fields, state helpers and visit evidence', () {
      final dto = PlaceReviewDto.fromJson({
        'id': 7,
        'lat': 45.46,
        'lon': 9.19,
        'radius_meters': 30,
        'state': 'CONFIRMED',
        'label': 'universita',
        'category': 'universita',
        'custom_name': '',
        'visit_count': 3,
        'distinct_days': 2,
        'visits': [
          {
            'lat': 45.46,
            'lon': 9.19,
            'started_at': '2026-06-12T10:00:00Z',
            'ended_at': '2026-06-12T10:06:00Z',
            'point_count': 4,
          },
        ],
      });

      expect(dto.id, 7);
      expect(dto.label, 'universita');
      expect(dto.isConfirmed, isTrue);
      expect(dto.isCandidate, isFalse);
      expect(dto.visitCount, 3);
      expect(dto.distinctDays, 2);
      expect(dto.visits, hasLength(1));
      expect(dto.visits.first.pointCount, 4);
      expect(dto.center.latitude, 45.46);
    });

    test('defaults missing optional fields', () {
      final dto = PlaceReviewDto.fromJson({
        'id': 1,
        'lat': 0.0,
        'lon': 0.0,
        'state': 'CANDIDATE',
        'label': 'luogo abituale',
      });

      expect(dto.category, '');
      expect(dto.customName, '');
      expect(dto.visits, isEmpty);
      expect(dto.isCandidate, isTrue);
    });
  });
}
