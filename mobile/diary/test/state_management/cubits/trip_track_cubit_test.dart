import 'dart:async';

import 'package:diary/features/common/domain/app_result.dart';
import 'package:diary/features/trips/domain/diary_event.dart';
import 'package:diary/features/trips/domain/trip_track.dart';
import 'package:diary/mappers/trips_mapper.dart';
import 'package:diary/network/dto/trip_track_dto.dart';
import 'package:diary/repositories/trip_track_repository.dart';
import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit.dart';
import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit_state.dart';
import 'package:flutter_test/flutter_test.dart';

final _mapper = TripsMapper();

TripTrack _trackFromJson(Map<String, dynamic> json) {
  return _mapper.mapTripTrack(TripTrackDto.fromJson(json));
}

TripDiary _diaryFromJson(Map<String, dynamic> json) {
  return _mapper.mapTripDiary(TripDiaryDto.fromJson(json));
}

class FakeTripTrackService implements TripTrackRepository {
  TripTrack? result;
  TripDiary? diary;
  final List<TripDiary> diaryResults = [];
  Object? error;
  int trackCalls = 0;
  int diaryCalls = 0;
  int eventStreamCalls = 0;
  final StreamController<DiaryEvent> events =
      StreamController<DiaryEvent>.broadcast();
  // Stream consumati in ordine per le singole chiamate a watchDiaryEvents;
  // se vuoto, si ricade su `events.stream` (broadcast a vita lunga).
  final List<Stream<DiaryEvent>> eventStreams = [];

  @override
  Future<AppResult<TripTrack>> fetchTrack(int tripId) async {
    trackCalls += 1;
    final failure = error;
    if (failure != null) return AppResult.failure(toAppFailure(failure));
    return AppResult.success(result!);
  }

  @override
  Future<AppResult<TripDiary>> fetchDiary(int tripId) async {
    diaryCalls += 1;
    final failure = error;
    if (failure != null) return AppResult.failure(toAppFailure(failure));
    if (diaryResults.isNotEmpty) {
      return AppResult.success(diaryResults.removeAt(0));
    }
    return AppResult.success(
      diary ??
          _diaryFromJson({
            'trip_id': tripId,
            'status': 'CLOSED',
            'processed': false,
            'segments': [],
            'places': [],
          }),
    );
  }

  @override
  Stream<DiaryEvent> watchDiaryEvents(int tripId) {
    eventStreamCalls += 1;
    final failure = error;
    if (failure != null) return Stream<DiaryEvent>.error(failure);
    if (eventStreams.isNotEmpty) return eventStreams.removeAt(0);
    return events.stream;
  }

  Future<void> close() => events.close();
}

void main() {
  group('TripTrackCubit', () {
    test('emits loaded when service returns points', () async {
      final service = FakeTripTrackService()
        ..result = _trackFromJson({
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
        ..diary = _diaryFromJson({
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
        ..diary = _diaryFromJson({
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
        ..result = _trackFromJson({
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
      final pendingDiary = _diaryFromJson({
        'trip_id': 1,
        'status': 'CLOSED',
        'processed': false,
        'segments': [],
        'places': [],
      });
      final enrichedDiary = _diaryFromJson({
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
        ..result = _trackFromJson({
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

      service.events.add(
        const DiaryEvent(status: DiaryEventStatus.enriched, tripId: 1),
      );
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

    test('surfaces diary enrichment failure without replacing the base track',
        () async {
      final service = FakeTripTrackService()
        ..result = _trackFromJson({
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
      addTearDown(service.close);
      addTearDown(cubit.close);

      await cubit.load(1);
      service.events.add(
        const DiaryEvent(
          status: DiaryEventStatus.failed,
          tripId: 1,
          reasonCode: 'diary_enrichment_failed',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.status, TripTrackStatus.loaded);
      expect(cubit.state.points, hasLength(2));
      expect(cubit.state.enrichmentPending, isFalse);
      expect(cubit.state.enrichmentFailed, isTrue);
      expect(cubit.state.enrichmentErrorMessage, contains('diario'));
      expect(service.events.hasListener, isFalse);
      expect(service.diaryCalls, 1);
      expect(service.trackCalls, 1);

      await cubit.reload();

      expect(cubit.state.status, TripTrackStatus.loaded);
      expect(cubit.state.enrichmentFailed, isTrue);
      expect(service.eventStreamCalls, 1);

      await cubit.load(1);

      expect(cubit.state.enrichmentPending, isTrue);
      expect(cubit.state.enrichmentFailed, isFalse);
      expect(service.eventStreamCalls, 2);
      expect(service.events.hasListener, isTrue);
    });

    test('re-watches diary after the SSE stream ends on timeout', () async {
      final service = FakeTripTrackService()
        ..result = _trackFromJson({
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
      // Primo watch: lo stream si chiude subito senza eventi, come fa il
      // backend dopo `: timeout` (300s senza arricchimento).
      service.eventStreams.add(const Stream<DiaryEvent>.empty());
      addTearDown(service.close);
      final cubit = TripTrackCubit(service);
      addTearDown(cubit.close);

      await cubit.load(1);
      // Lascia scattare l'onDone dello stream completato.
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.enrichmentPending, isTrue);
      expect(service.eventStreamCalls, 1);

      // Dopo il timeout, un refresh manuale deve riaprire la SSE: senza
      // l'azzeramento su onDone la guardia `!= null` lo bloccherebbe.
      await cubit.reload();

      expect(service.eventStreamCalls, 2);
      expect(service.events.hasListener, isTrue);
    });

    test('emits empty when service returns no GeoJSON', () async {
      final service = FakeTripTrackService()
        ..result = _trackFromJson({
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
        ..result = _trackFromJson({
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
        ..result = _trackFromJson({
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
