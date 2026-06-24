import 'package:diary/network/service/trip_track_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseDiaryEvents', () {
    test('parses diary status event payloads and skips keep alive comments',
        () async {
      final events = await parseDiaryEvents(
        Stream.fromIterable([
          ': waiting',
          '',
          'event: diary_status',
          'data: {"trip_id":4,"status":"failed","reason":"diary_enrichment_failed"}',
          '',
        ]),
      ).toList();

      expect(events, hasLength(1));
      expect(events.single.status, DiaryEventStatus.failed);
      expect(events.single.tripId, 4);
      expect(events.single.reasonCode, 'diary_enrichment_failed');
    });

    test('returns unknown for malformed data and unknown statuses', () async {
      final events = await parseDiaryEvents(
        Stream.fromIterable([
          'event: diary_status',
          'data: not-json',
          '',
          'event: diary_status',
          'data: {"trip_id":4,"status":"other"}',
          '',
        ]),
      ).toList();

      expect(events.map((event) => event.status), [
        DiaryEventStatus.unknown,
        DiaryEventStatus.unknown,
      ]);
    });
  });
}
