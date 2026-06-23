import 'dart:async';

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
  int eventStreamCalls = 0;
  final StreamController<String> events = StreamController<String>.broadcast();

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

  @override
  Stream<String> watchDiaryEvents(int tripId) {
    eventStreamCalls += 1;
    final failure = error;
    if (failure != null) return Stream<String>.error(failure);
    return events.stream;
  }

  Future<void> close() => events.close();
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
      addTearDown(service.close);
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
      expect(service.eventStreamCalls, 1);
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
      addTearDown(service.close);
      final cubit = TripTrackCubit(service);
      addTearDown(cubit.close);

      await cubit.load(1);

      expect(cubit.state.status, TripTrackStatus.loaded);
      expect(cubit.state.isSegmented, isTrue);
      expect(cubit.state.segments, hasLength(2));
      expect(cubit.state.diarySegments, hasLength(2));
      expect(cubit.state.segments.first.activityLabel, 'BIKING');
      expect(cubit.state.points, hasLength(4));
      expect(cubit.state.distanceMeters, 850);
      expect(cubit.state.enrichmentPending, isFalse);
      expect(service.diaryCalls, 1);
      expect(service.trackCalls, 0);
      expect(service.eventStreamCalls, 0);
    });

    test('keeps processed diary segments when the map falls back to base track',
        () async {
      final service = FakeTripTrackService()
        ..diary = TripDiaryDto.fromJson({
          'trip_id': 1,
          'status': 'PROCESSED',
          'processed': true,
          'segments': [
            {
              'kind': 'STOP',
              'start_timestamp': '2026-06-12T10:00:00Z',
              'end_timestamp': '2026-06-12T10:10:00Z',
              'activity_label': 'IDLE',
              'distance_meters': 0,
              'path_geojson': null,
              'place': {
                'id': 7,
                'lat': 45.47,
                'lon': 9.20,
                'radius_meters': 30,
                'dwell_seconds': 600,
                'label': 'Casa',
              },
            },
          ],
          'places': [],
        })
        ..result = TripTrackDto.fromJson({
          'trip_id': 1,
          'point_count': 2,
          'distance_meters': 120,
          'geojson': {
            'type': 'LineString',
            'coordinates': [
              [9.10, 45.46],
              [9.20, 45.47],
            ],
          },
        });
      addTearDown(service.close);
      final cubit = TripTrackCubit(service);
      addTearDown(cubit.close);

      await cubit.load(1);

      expect(cubit.state.status, TripTrackStatus.loaded);
      expect(cubit.state.points, hasLength(2));
      expect(cubit.state.segments, isEmpty);
      expect(cubit.state.diarySegments.single.kind, 'STOP');
      expect(cubit.state.enrichmentPending, isFalse);
    });

    test('refetches pending diary after diary enriched event', () async {
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
      final cubit = TripTrackCubit(service);
      addTearDown(service.close);
      addTearDown(cubit.close);

      await cubit.load(1);

      expect(cubit.state.isSegmented, isFalse);
      expect(cubit.state.enrichmentPending, isTrue);
      expect(service.trackCalls, 1);
      expect(service.eventStreamCalls, 1);

      service.events.add('diary_enriched');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.status, TripTrackStatus.loaded);
      expect(cubit.state.isSegmented, isTrue);
      expect(cubit.state.segments.single.activityLabel, 'RUNNING');
      expect(cubit.state.enrichmentPending, isFalse);
      expect(service.diaryCalls, 2);
      expect(service.trackCalls, 1);
      expect(service.eventStreamCalls, 1);
    });

    test('emits empty when service returns no GeoJSON', () async {
      final service = FakeTripTrackService()
        ..result = TripTrackDto.fromJson({
          'trip_id': 1,
          'point_count': 1,
          'distance_meters': 0,
          'geojson': null,
        });
      addTearDown(service.close);
      final cubit = TripTrackCubit(service);
      addTearDown(cubit.close);

      await cubit.load(1);

      expect(cubit.state.status, TripTrackStatus.empty);
      expect(cubit.state.points, isEmpty);
      expect(cubit.state.distanceMeters, 0);
      expect(service.eventStreamCalls, 1);
    });

    test('manual retry keeps the last base track when the network fails',
        () async {
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
      addTearDown(service.close);
      final cubit = TripTrackCubit(service);
      addTearDown(cubit.close);

      await cubit.load(1);
      service.error = Exception('offline');
      await cubit.reload();

      expect(cubit.state.status, TripTrackStatus.error);
      expect(cubit.state.error, contains('offline'));
      expect(cubit.state.points, hasLength(2));
      expect(cubit.state.distanceMeters, 900);
      expect(cubit.state.enrichmentPending, isTrue);
    });

    test('closes the diary event stream when disposed', () async {
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
      addTearDown(service.close);
      final cubit = TripTrackCubit(service);

      await cubit.load(1);
      expect(service.events.hasListener, isTrue);

      await cubit.close();

      expect(service.events.hasListener, isFalse);
    });

    test('emits error when service fails', () async {
      final service = FakeTripTrackService()..error = Exception('boom');
      addTearDown(service.close);
      final cubit = TripTrackCubit(service);
      addTearDown(cubit.close);

      await cubit.load(1);

      expect(cubit.state.status, TripTrackStatus.error);
      expect(cubit.state.error, contains('boom'));
    });
  });
}
