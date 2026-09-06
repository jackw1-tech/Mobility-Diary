import 'dart:async';

import 'package:diary/model/entities/trips/trip_enums.dart';
import 'package:diary/model/entities/trips/trip_track.dart';
import 'package:diary/repositories/trip_track_repository.dart';
import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit.dart';
import 'package:diary/state_management/cubits/trip_track_cubit/trip_diary_load_policy.dart';
import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit_state.dart';
import 'package:diary/utils/app_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('diary load policy caps exponential retry delays', () {
    const policy = TripDiaryLoadPolicy(
      retryBaseDelay: Duration(seconds: 2),
      retryMaxDelay: Duration(seconds: 5),
    );

    expect(policy.retryDelay(1), const Duration(seconds: 2));
    expect(policy.retryDelay(2), const Duration(seconds: 4));
    expect(policy.retryDelay(3), const Duration(seconds: 5));
  });

  test('shows an enriched diary without waiting for a slow track', () async {
    final trackResult = Completer<AppResult<TripTrack>>();
    final repository = _FakeTripTrackRepository(
      fetchTrack: (_) => trackResult.future,
      fetchDiary: (_) async => AppResult.success(_enrichedDiary()),
    );
    final cubit = TripTrackCubit(repository);
    addTearDown(cubit.close);

    unawaited(cubit.load(1));
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(cubit.state.status, TripTrackStatus.loaded);
    expect(cubit.state.points, hasLength(2));
    expect(cubit.state.segments, hasLength(1));

    trackResult.complete(AppResult.success(_track()));
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.points, hasLength(3));
    expect(cubit.state.trackStatus, TrackLoadStatus.loaded);
  });

  test('polls only the diary while enrichment is pending', () async {
    var trackRequests = 0;
    var diaryRequests = 0;
    final repository = _FakeTripTrackRepository(
      fetchTrack: (_) async {
        trackRequests += 1;
        return AppResult.success(_track());
      },
      fetchDiary: (_) async {
        diaryRequests += 1;
        return AppResult.success(_pendingDiary());
      },
    );
    final cubit = TripTrackCubit(repository);
    addTearDown(cubit.close);

    await cubit.load(1);
    final segmentsBeforePoll = cubit.state.segments;
    final diarySegmentsBeforePoll = cubit.state.diarySegments;
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    expect(cubit.state.status, TripTrackStatus.loaded);
    expect(cubit.state.diaryStatus, DiaryLoadStatus.pending);
    expect(trackRequests, 1);
    expect(diaryRequests, greaterThanOrEqualTo(2));
    expect(
      identical(cubit.state.segments, segmentsBeforePoll),
      isTrue,
      reason: 'un diario invariato non deve ridisegnare la mappa',
    );
    expect(
        identical(cubit.state.diarySegments, diarySegmentsBeforePoll), isTrue);
  });

  test('reuses the page-scoped track when the same trip is reloaded', () async {
    var trackRequests = 0;
    var diaryRequests = 0;
    final repository = _FakeTripTrackRepository(
      fetchTrack: (_) async {
        trackRequests += 1;
        return AppResult.success(_track());
      },
      fetchDiary: (_) async {
        diaryRequests += 1;
        return AppResult.success(_enrichedDiary());
      },
    );
    final cubit = TripTrackCubit(repository);
    addTearDown(cubit.close);

    await cubit.load(1);
    await cubit.reload();

    expect(cubit.state.status, TripTrackStatus.loaded);
    expect(trackRequests, 1);
    expect(diaryRequests, 2);
  });

  test('reuses equal diary segments during an in-place refresh', () async {
    var diaryRequests = 0;
    final repository = _FakeTripTrackRepository(
      fetchTrack: (_) async => AppResult.success(_track()),
      fetchDiary: (_) async {
        diaryRequests += 1;
        return AppResult.success(_enrichedDiary());
      },
    );
    final cubit = TripTrackCubit(repository);
    addTearDown(cubit.close);

    await cubit.load(1);
    final segmentsBeforeRefresh = cubit.state.diarySegments;
    await cubit.retryDiaryNow();

    expect(diaryRequests, 2);
    expect(identical(cubit.state.diarySegments, segmentsBeforeRefresh), isTrue);
  });

  test('uses diary geometry when track loading fails', () async {
    final repository = _FakeTripTrackRepository(
      fetchTrack: (_) async => const AppResult.failure(
        NetworkFailure('traccia non disponibile'),
      ),
      fetchDiary: (_) async => AppResult.success(_enrichedDiary()),
    );
    final cubit = TripTrackCubit(repository);
    addTearDown(cubit.close);

    await cubit.load(1);

    expect(cubit.state.status, TripTrackStatus.loaded);
    expect(cubit.state.trackStatus, TrackLoadStatus.failed);
    expect(cubit.state.diaryStatus, DiaryLoadStatus.loaded);
    expect(cubit.state.points, hasLength(2));
    expect(cubit.state.error, isNull);
  });

  test('keeps the map available when diary loading fails', () async {
    final repository = _FakeTripTrackRepository(
      fetchTrack: (_) async => AppResult.success(_track()),
      fetchDiary: (_) async => const AppResult.failure(
        NetworkFailure('diario non disponibile'),
      ),
    );
    final cubit = TripTrackCubit(repository);
    addTearDown(cubit.close);

    await cubit.load(1);

    expect(cubit.state.status, TripTrackStatus.loaded);
    expect(cubit.state.trackStatus, TrackLoadStatus.loaded);
    expect(cubit.state.diaryStatus, DiaryLoadStatus.failed);
    expect(cubit.state.points, hasLength(3));
    expect(
      cubit.state.enrichmentFailed,
      isFalse,
      reason: 'un errore di rete non e\' un fallimento dell\'arricchimento',
    );
    expect(cubit.state.diaryRetryPending, isTrue);
    expect(cubit.state.diaryError, 'diario non disponibile');
    expect(cubit.state.error, isNull);
  });

  test('retries the diary with backoff instead of stopping the polling',
      () async {
    var diaryRequests = 0;
    final repository = _FakeTripTrackRepository(
      fetchTrack: (_) async => AppResult.success(_track()),
      fetchDiary: (_) async {
        diaryRequests += 1;
        if (diaryRequests <= 2) {
          return const AppResult.failure(NetworkFailure('rete assente'));
        }
        return AppResult.success(_enrichedDiary());
      },
    );
    final cubit = TripTrackCubit(
      repository,
      diaryLoadPolicy: const TripDiaryLoadPolicy(
        pollingInterval: Duration(milliseconds: 10),
        retryBaseDelay: Duration(milliseconds: 20),
        retryMaxDelay: Duration(milliseconds: 60),
      ),
    );
    addTearDown(cubit.close);

    await cubit.load(1);
    expect(cubit.state.diaryStatus, DiaryLoadStatus.failed);
    expect(cubit.state.diaryRetryPending, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(diaryRequests, greaterThanOrEqualTo(3));
    expect(cubit.state.diaryStatus, DiaryLoadStatus.loaded);
    expect(cubit.state.diaryRetryPending, isFalse);
    expect(cubit.state.segments, hasLength(1));
  });

  test('a hung diary request does not block the following attempts', () async {
    var diaryRequests = 0;
    final repository = _FakeTripTrackRepository(
      fetchTrack: (_) async => AppResult.success(_track()),
      fetchDiary: (_) async {
        diaryRequests += 1;
        if (diaryRequests == 1) return Completer<AppResult<TripDiary>>().future;
        return AppResult.success(_enrichedDiary());
      },
    );
    final cubit = TripTrackCubit(
      repository,
      diaryLoadPolicy: const TripDiaryLoadPolicy(
        pollingInterval: Duration(milliseconds: 10),
        requestTimeout: Duration(milliseconds: 40),
        retryBaseDelay: Duration(milliseconds: 20),
        retryMaxDelay: Duration(milliseconds: 60),
      ),
    );
    addTearDown(cubit.close);

    await cubit.load(1);
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(diaryRequests, greaterThanOrEqualTo(2));
    expect(cubit.state.diaryStatus, DiaryLoadStatus.loaded);
  });

  test('a definitive enrichment failure stops the polling', () async {
    var diaryRequests = 0;
    final repository = _FakeTripTrackRepository(
      fetchTrack: (_) async => AppResult.success(_track()),
      fetchDiary: (_) async {
        diaryRequests += 1;
        return AppResult.success(_failedDiary());
      },
    );
    final cubit = TripTrackCubit(
      repository,
      diaryLoadPolicy: const TripDiaryLoadPolicy(
        pollingInterval: Duration(milliseconds: 10),
      ),
    );
    addTearDown(cubit.close);

    await cubit.load(1);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(diaryRequests, 1);
    expect(cubit.state.diaryStatus, DiaryLoadStatus.failed);
    expect(cubit.state.enrichmentFailed, isTrue);
    expect(cubit.state.diaryRetryPending, isFalse);
  });

  test('shows a full error only when track and diary both fail', () async {
    final repository = _FakeTripTrackRepository(
      fetchTrack: (_) async => const AppResult.failure(
        NetworkFailure('traccia non disponibile'),
      ),
      fetchDiary: (_) async => const AppResult.failure(
        NetworkFailure('diario non disponibile'),
      ),
    );
    final cubit = TripTrackCubit(repository);
    addTearDown(cubit.close);

    await cubit.load(1);

    expect(cubit.state.status, TripTrackStatus.error);
    expect(cubit.state.points, isEmpty);
    expect(cubit.state.error, 'diario non disponibile');
  });

  test('ignores stale responses after switching trip', () async {
    final oldTrack = Completer<AppResult<TripTrack>>();
    final oldDiary = Completer<AppResult<TripDiary>>();
    final repository = _FakeTripTrackRepository(
      fetchTrack: (tripId) => tripId == 1
          ? oldTrack.future
          : Future.value(AppResult.success(_track(tripId: 2))),
      fetchDiary: (tripId) => tripId == 1
          ? oldDiary.future
          : Future.value(AppResult.success(_enrichedDiary(tripId: 2))),
    );
    final cubit = TripTrackCubit(repository);
    addTearDown(cubit.close);

    unawaited(cubit.load(1));
    await Future<void>.delayed(Duration.zero);
    await cubit.load(2);
    oldTrack.complete(AppResult.success(_track(tripId: 1)));
    oldDiary.complete(AppResult.success(_enrichedDiary(tripId: 1)));
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state.tripId, 2);
    expect(cubit.state.status, TripTrackStatus.loaded);
    expect(cubit.state.trackStatus, TrackLoadStatus.loaded);
    expect(cubit.state.diaryStatus, DiaryLoadStatus.loaded);
  });
}

class _FakeTripTrackRepository implements TripTrackRepository {
  final Future<AppResult<TripTrack>> Function(int tripId) _fetchTrack;
  final Future<AppResult<TripDiary>> Function(int tripId) _fetchDiary;

  _FakeTripTrackRepository({
    required Future<AppResult<TripTrack>> Function(int tripId) fetchTrack,
    required Future<AppResult<TripDiary>> Function(int tripId) fetchDiary,
  })  : _fetchTrack = fetchTrack,
        _fetchDiary = fetchDiary;

  @override
  Future<AppResult<TripTrack>> fetchTrack(int tripId) => _fetchTrack(tripId);

  @override
  Future<AppResult<TripDiary>> fetchDiary(int tripId) => _fetchDiary(tripId);
}

TripTrack _track({int tripId = 1}) => TripTrack(
      tripId: tripId,
      pointCount: 3,
      distanceMeters: 200,
      geojson: const {
        'type': 'LineString',
        'coordinates': [
          [9.0, 45.0],
          [9.1, 45.1],
          [9.2, 45.2],
        ],
      },
    );

TripDiary _enrichedDiary({int tripId = 1}) => TripDiary(
      tripId: tripId,
      status: TripDiaryStatus.enriched,
      enrichmentCompleted: true,
      enrichmentFailed: false,
      segments: [
        TripDiarySegment(
          kind: TripDiarySegmentKind.move,
          startTimestamp: DateTime.utc(2026, 9, 3, 10),
          endTimestamp: DateTime.utc(2026, 9, 3, 10, 5),
          activity: MobilityActivity.walking,
          distanceMeters: 150,
          pathGeojson: const {
            'type': 'LineString',
            'coordinates': [
              [9.0, 45.0],
              [9.1, 45.1],
            ],
          },
        ),
      ],
      places: const [],
    );

TripDiary _pendingDiary({int tripId = 1}) => TripDiary(
      tripId: tripId,
      status: TripDiaryStatus.closed,
      enrichmentCompleted: false,
      enrichmentFailed: false,
      segments: const [],
      places: const [],
    );

TripDiary _failedDiary({int tripId = 1}) => TripDiary(
      tripId: tripId,
      status: TripDiaryStatus.closed,
      enrichmentCompleted: false,
      enrichmentFailed: true,
      enrichmentFailureReason: 'diary_enrichment_failed',
      segments: const [],
      places: const [],
    );
