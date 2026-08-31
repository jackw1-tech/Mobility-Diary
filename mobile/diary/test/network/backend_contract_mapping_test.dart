import 'package:diary/mappers/ingestion_mapper.dart';
import 'package:diary/mappers/privacy_settings_mapper.dart';
import 'package:diary/mappers/trips_mapper.dart';
import 'package:diary/model/entities/privacy/privacy_level.dart';
import 'package:diary/model/entities/trips/trip_enums.dart';
import 'package:diary/network/dto/ingestion/ingestion_status_dto.dart';
import 'package:diary/network/dto/privacy_settings_dto.dart';
import 'package:diary/network/dto/trip_list_item_dto.dart';
import 'package:diary/network/dto/trip_track_dto.dart';
import 'package:diary/network/service/trip_ingestion_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps the backend ingestion status contract without losing part keys',
      () {
    final dto = IngestionStatusDto.fromJson({
      'ingestion_id': 7,
      'core_status': 'COMPLETED',
      'raw_status': 'RECEIVING',
      'missing_raw_parts': [
        {'sequence': 2},
        {'sequence': 4},
      ],
      'trip_id': 12,
      'map_available': true,
    });

    final status = IngestionMapper().mapIngestionStatus(dto);

    expect(status.coreStatus, 'COMPLETED');
    expect(status.rawStatus, 'RECEIVING');
    expect(status.missingRawParts, [2, 4]);
    expect(status.tripId, 12);
    expect(status.mapAvailable, isTrue);
  });

  test('parses the active recording embedded in a backend conflict', () {
    const error = IngestionApiException(
      'conflict',
      statusCode: 409,
      body: {
        'active_ingestion': {
          'ingestion_id': 9,
          'client_session_id': 'session-active',
          'device_id': 'iphone-owner',
          'recording_started_at': '2026-08-30T10:00:00Z',
          'last_seen_at': '2026-08-30T10:01:00Z',
        },
      },
    );

    final active = activeIngestionFromConflict(error);

    expect(active?.ingestionId, 9);
    expect(active?.clientSessionId, 'session-active');
    expect(active?.deviceId, 'iphone-owner');
  });

  test('maps trip list capabilities returned by the backend', () {
    final dto = TripListItemDto.fromJson({
      'id': 3,
      'started_at': '2026-08-30T10:00:00Z',
      'ended_at': '2026-08-30T10:10:00Z',
      'status': 'PROCESSED',
      'distance_meters': 1250.5,
      'note': 'Universita',
      'has_track': true,
      'is_reloadable': true,
      'is_derived': false,
      'can_delete': true,
      'can_toggle_reloadable': true,
      'can_edit_note': true,
    });

    final trip = TripsMapper().mapTripListItem(dto);

    expect(trip.tripStatus, TripStatus.processed);
    expect(trip.startedAt.isUtc, isTrue);
    expect(trip.distanceMeters, 1250.5);
    expect(trip.note, 'Universita');
    expect(trip.isReloadable, isTrue);
    expect(trip.canEditNote, isTrue);
  });

  test('maps diary geometry into drawable latitude/longitude points', () {
    final dto = TripDiaryDto.fromJson({
      'trip_id': 3,
      'status': 'PROCESSED',
      'processed': true,
      'segments': [
        {
          'kind': 'MOVE',
          'start_timestamp': '2026-08-30T10:00:00Z',
          'end_timestamp': '2026-08-30T10:10:00Z',
          'activity_label': 'WALKING',
          'distance_meters': 650,
          'path_geojson': {
            'type': 'LineString',
            'coordinates': [
              [9.19, 45.46],
              [9.20, 45.47],
            ],
          },
        },
      ],
      'places': [],
    });

    final diary = TripsMapper().mapTripDiary(dto);

    expect(diary.diaryStatus, TripDiaryStatus.processed);
    expect(diary.drawableSegments.length, 1);
    expect(diary.drawableSegments.single.points.first.latitude, 45.46);
    expect(diary.drawableSegments.single.points.first.longitude, 9.19);
  });

  test('unknown privacy levels fail closed to the precise app default', () {
    final settings = PrivacySettingsMapper().mapSettings(
      const PrivacySettingsDto(
        privacyLevel: 'future-level',
        isFirstLogin: false,
      ),
    );

    expect(settings.level, PrivacyLevel.precise);
    expect(settings.isFirstLogin, isFalse);
  });
}
