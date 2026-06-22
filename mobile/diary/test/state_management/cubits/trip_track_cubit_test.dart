import 'package:diary/network/dto/trip_track_dto.dart';
import 'package:diary/network/service/trip_track_service.dart';
import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit.dart';
import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit_state.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeTripTrackService implements TripTrackService {
  TripTrackDto? result;
  TripDiaryDto? diary;
  final List<TripDiaryDto> diaryResults = [];
  Object? error;
  int trackCalls = 0;
  int diaryCalls = 0;

  @override
  Future<TripTrackDto> fetchTrack(int tripId) async {
    trackCalls += 1;
    final failure = error;
    if (failure != null) throw failure;
    return result!;
  }

  @override
  Future<TripDiaryDto> fetchDiary(int tripId) async {
    diaryCalls += 1;
    final failure = error;
    if (failure != null) throw failure;
    if (diaryResults.isNotEmpty) {
      return diaryResults.removeAt(0);
    }
    return diary ??
        TripDiaryDto.fromJson({
          'trip_id': tripId,
          'status': 'CLOSED',
          'processed': false,
          'segments': [],
          'places': [],
        });
  }
}

void main() {
  group('TripTrackCubit', () {
    test('emits loaded when service returns points', () async {
      final service = FakeTripTrackService()
        ..result = TripTrackDto.fromJson({
          'trip_id': 1,
          'point_count': 2,
          'distance_meters': 900,
          'geojson': {
            'type': 'LineString',
            'coordinates': [
              [9.10, 45.46],
              [9.20, 45.47],
            ],
          },
        });
      final cubit = TripTrackCubit(service);
      addTearDown(cubit.close);

      await cubit.load(1);

      expect(cubit.state.status, TripTrackStatus.loaded);
      expect(cubit.state.points, hasLength(2));
      expect(cubit.state.segments, isEmpty);
      expect(cubit.state.distanceMeters, 900);
      expect(cubit.state.enrichmentPending, isTrue);
      expect(service.diaryCalls, 1);
      expect(service.trackCalls, 1);
    });

    test('emits segmented track when diary has enriched movement geometry',
        () async {
      final service = FakeTripTrackService()
        ..diary = TripDiaryDto.fromJson({
          'trip_id': 1,
          'status': 'PROCESSED',
          'processed': true,
          'segments': [
            {
              'kind': 'MOVE',
              'start_timestamp': '2026-06-12T10:00:00Z',
              'end_timestamp': '2026-06-12T10:05:00Z',
              'activity_label': 'BIKING',
              'distance_meters': 500,
              'path_geojson': {
                'type': 'LineString',
                'coordinates': [
                  [9.10, 45.46],
                  [9.15, 45.47],
                ],
              },
              'place': null,
            },
            {
              'kind': 'MOVE',
              'start_timestamp': '2026-06-12T10:05:00Z',
              'end_timestamp': '2026-06-12T10:10:00Z',
              'activity_label': 'WALKING',
              'distance_meters': 350,
              'path_geojson': {
                'type': 'LineString',
                'coordinates': [
                  [9.15, 45.47],
                  [9.20, 45.48],
                ],
              },
              'place': null,
            },
          ],
          'places': [],
        });
      final cubit = TripTrackCubit(service);
      addTearDown(cubit.close);

      await cubit.load(1);

      expect(cubit.state.status, TripTrackStatus.loaded);
      expect(cubit.state.isSegmented, isTrue);
      expect(cubit.state.segments, hasLength(2));
      expect(cubit.state.segments.first.activityLabel, 'BIKING');
      expect(cubit.state.points, hasLength(4));
      expect(cubit.state.distanceMeters, 850);
      expect(cubit.state.enrichmentPending, isFalse);
      expect(service.diaryCalls, 1);
      expect(service.trackCalls, 0);
    });

    test('polls pending diary and switches from base track to segments',
        () async {
      final pendingDiary = TripDiaryDto.fromJson({
        'trip_id': 1,
        'status': 'CLOSED',
        'processed': false,
        'segments': [],
        'places': [],
      });
      final enrichedDiary = TripDiaryDto.fromJson({
        'trip_id': 1,
        'status': 'PROCESSED',
        'processed': true,
        'segments': [
          {
            'kind': 'MOVE',
            'start_timestamp': '2026-06-12T10:00:00Z',
            'end_timestamp': '2026-06-12T10:05:00Z',
            'activity_label': 'RUNNING',
            'distance_meters': 400,
            'path_geojson': {
              'type': 'LineString',
              'coordinates': [
                [9.10, 45.46],
                [9.12, 45.47],
              ],
            },
            'place': null,
          },
        ],
        'places': [],
      });
      final service = FakeTripTrackService()
        ..result = TripTrackDto.fromJson({
          'trip_id': 1,
          'point_count': 2,
          'distance_meters': 900,
          'geojson': {
            'type': 'LineString',
            'coordinates': [
              [9.10, 45.46],
              [9.20, 45.47],
            ],
          },
        });
      service.diaryResults.addAll([pendingDiary, enrichedDiary]);
      final cubit = TripTrackCubit(
        service,
        pollDelay: Duration.zero,
        maxPendingPolls: 1,
      );
      addTearDown(cubit.close);

      await cubit.load(1);

      expect(cubit.state.isSegmented, isFalse);
      expect(cubit.state.enrichmentPending, isTrue);
      expect(service.trackCalls, 1);

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.status, TripTrackStatus.loaded);
      expect(cubit.state.isSegmented, isTrue);
      expect(cubit.state.segments.single.activityLabel, 'RUNNING');
      expect(cubit.state.enrichmentPending, isFalse);
      expect(service.diaryCalls, 2);
      expect(service.trackCalls, 1);
    });

    test('emits empty when service returns no GeoJSON', () async {
      final service = FakeTripTrackService()
        ..result = TripTrackDto.fromJson({
          'trip_id': 1,
          'point_count': 1,
          'distance_meters': 0,
          'geojson': null,
        });
      final cubit = TripTrackCubit(service);
      addTearDown(cubit.close);

      await cubit.load(1);

      expect(cubit.state.status, TripTrackStatus.empty);
      expect(cubit.state.points, isEmpty);
      expect(cubit.state.distanceMeters, 0);
    });

    test('emits error when service fails', () async {
      final service = FakeTripTrackService()..error = Exception('boom');
      final cubit = TripTrackCubit(service);
      addTearDown(cubit.close);

      await cubit.load(1);

      expect(cubit.state.status, TripTrackStatus.error);
      expect(cubit.state.error, contains('boom'));
    });
  });
}
