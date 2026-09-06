import 'dart:async';

import 'package:diary/model/entities/trips/trip_track.dart';
import 'package:diary/repositories/trip_track_repository.dart';
import 'package:diary/state_management/cubits/trip_track_cubit/trip_diary_load_policy.dart';
import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit_state.dart';
import 'package:diary/utils/app_result.dart';
import 'package:diary/utils/trip_detail_diagnostics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class TripTrackCubit extends Cubit<TripTrackCubitState> {
  final TripTrackRepository _repository;
  final TripDiaryLoadPolicy _diaryLoadPolicy;
  final Map<int, TripTrack> _trackCache = {};
  Timer? _diaryPollingTimer;
  int? _tripId;
  String? _diagnosticsTraceId;
  int _loadGeneration = 0;
  int _diaryFailureStreak = 0;

  TripTrackCubit(
    this._repository, {
    TripDiaryLoadPolicy diaryLoadPolicy = const TripDiaryLoadPolicy(),
  })  : _diaryLoadPolicy = diaryLoadPolicy,
        super(const TripTrackCubitState.initial());

  // Funzione richiamata dal cubit che chiede i dati del singolo viaggio in Trip Detail Page
  Future<void> load(int tripId, {String? diagnosticsTraceId}) {
    _tripId = tripId;
    _diagnosticsTraceId = diagnosticsTraceId;
    return _startLoad(tripId);
  }

  Future<void> reload() async {
    final tripId = _tripId;
    if (tripId == null) return;
    await _startLoad(tripId);
  }

  /// Ritenta subito il diario senza ricaricare la traccia gia' disegnata.
  /// Serve al pulsante di riprova: l'attesa del backoff viene azzerata.
  Future<void> retryDiaryNow() async {
    final tripId = _tripId;
    if (tripId == null) return;
    _stopDiaryPolling();
    _diaryFailureStreak = 0;
    TripDetailDiagnostics.event(_diagnosticsTraceId, 'diary_manual_retry');
    await _loadDiary(tripId, _loadGeneration, pollPendingDiary: true);
  }

  // Fa due chiamate parallele, una per il diario e una per la traccia del viaggio
  Future<void> _startLoad(int tripId) async {
    final generation =
        ++_loadGeneration; // Protezione race condition quando cambio velocemente da un viaggio allìaltro
    final traceId = _diagnosticsTraceId;
    _stopDiaryPolling();
    _diaryFailureStreak = 0;
    emit(
      TripTrackCubitState(
        tripId: tripId,
        diagnosticsTraceId: traceId,
        status: TripTrackStatus.loading,
        trackStatus: TrackLoadStatus.loading,
        diaryStatus: DiaryLoadStatus.loading,
      ),
    );
    TripDetailDiagnostics.event(
      traceId,
      'track_cubit_load_start',
      fields: {'generation': generation},
    );
    TripDetailDiagnostics.event(traceId, 'parallel_requests_started');

    await Future.wait([
      _loadTrack(tripId, generation),
      _loadDiary(tripId, generation, pollPendingDiary: true),
    ]);
  }

  //
  Future<void> _loadTrack(int tripId, int generation) async {
    final cached = _trackCache[tripId];
    final AppResult<TripTrack> result;
    if (cached != null) {
      TripDetailDiagnostics.event(
        _diagnosticsTraceId,
        'track_page_cache_hit',
        fields: {'trip_id': tripId},
      );
      result = AppResult.success(cached);
    } else {
      result = await _safeTimedFetch(
        _diagnosticsTraceId,
        'track_repository_future',
        () => _repository.fetchTrack(tripId),
      );
    }
    if (!_isCurrent(tripId, generation)) return;

    final failure = result.failure;
    if (failure != null) {
      _emitResolved(
        state.copyWith(
          trackStatus: TrackLoadStatus.failed,
          trackError: failure.message,
        ),
      );
      return;
    }

    final track = result.requireValue;
    _trackCache[tripId] = track;
    final points = track.points;
    final diaryProvidesDistance = state.diaryStatus == DiaryLoadStatus.loaded &&
        state.diarySegments.isNotEmpty;
    final next = state.copyWith(
      trackStatus: TrackLoadStatus.loaded,
      points: points.isEmpty ? state.points : points,
      distanceMeters:
          diaryProvidesDistance ? state.distanceMeters : track.distanceMeters,
      trackError: null,
    );
    TripDetailDiagnostics.event(
      _diagnosticsTraceId,
      'track_result_applied',
      fields: {'generation': generation, 'point_count': points.length},
    );
    _emitResolved(next);
  }

  Future<void> _loadDiary(
    int tripId,
    int generation, {
    required bool pollPendingDiary,
  }) async {
    final result = await _safeTimedFetch(
      _diagnosticsTraceId,
      'diary_repository_future',
      () => _repository.fetchDiary(tripId),
      timeout: _diaryLoadPolicy.requestTimeout,
    );
    if (!_isCurrent(tripId, generation)) return;

    final failure = result.failure;
    if (failure != null) {
      _diaryFailureStreak += 1;
      final retryDelay = _diaryLoadPolicy.retryDelay(_diaryFailureStreak);
      final keepsPreviousDiary = state.diaryStatus == DiaryLoadStatus.loaded ||
          state.diaryStatus == DiaryLoadStatus.pending;
      TripDetailDiagnostics.event(
        _diagnosticsTraceId,
        'diary_fetch_failure',
        fields: {
          'generation': generation,
          'failure_type': failure.runtimeType,
          'failure_streak': _diaryFailureStreak,
          'retry_in_ms': pollPendingDiary ? retryDelay.inMilliseconds : null,
          'keeps_previous_diary': keepsPreviousDiary,
        },
      );
      _emitResolved(
        state.copyWith(
          diaryStatus:
              keepsPreviousDiary ? state.diaryStatus : DiaryLoadStatus.failed,
          enrichmentFailed: false,
          enrichmentErrorMessage: null,
          diaryError: keepsPreviousDiary ? null : failure.message,
          diaryRetryPending: pollPendingDiary,
        ),
      );
      if (pollPendingDiary) {
        _scheduleDiaryPoll(tripId, generation, delay: retryDelay);
      } else {
        _stopDiaryPolling();
      }
      return;
    }
    _diaryFailureStreak = 0;

    final diary = result.requireValue;
    TripDetailDiagnostics.event(
      _diagnosticsTraceId,
      'diary_result_available',
      fields: {
        'enrichment_completed': diary.enrichmentCompleted,
        'segment_count': diary.segments.length,
        'place_count': diary.places.length,
        'generation': generation,
      },
    );
    final enrichmentFailed =
        !diary.enrichmentCompleted && diary.enrichmentFailed;
    final enrichmentPending = !diary.enrichmentCompleted && !enrichmentFailed;
    final segments = [
      for (final segment in diary.drawableSegments)
        TripTrackSegmentState(
          points: segment.points,
          activityLabel: segment.activityLabel,
          distanceMeters: segment.distanceMeters,
          startTimestamp: segment.startTimestamp,
          endTimestamp: segment.endTimestamp,
        ),
    ];
    final fallbackPoints = [
      for (final segment in segments) ...segment.points,
    ];
    final diaryStatus = enrichmentFailed
        ? DiaryLoadStatus.failed
        : enrichmentPending
            ? DiaryLoadStatus.pending
            : DiaryLoadStatus.loaded;
    final failureMessage = enrichmentFailed
        ? _enrichmentFailureMessage(diary.enrichmentFailureReason)
        : null;
    // Il polling ripete la stessa risposta ogni secondo: se il contenuto non
    // e' cambiato si riusa la stessa istanza di lista, cosi' la mappa non
    // rilegge come "nuovi" segmenti identici e non ridisegna nulla.
    final nextSegments = _sameList(state.segments, segments, _sameTrackSegment)
        ? state.segments
        : segments;
    final rawDiarySegments =
        diary.enrichmentCompleted ? diary.segments : const <TripDiarySegment>[];
    final nextDiarySegments = _sameList(
      state.diarySegments,
      rawDiarySegments,
      _sameDiarySegment,
    )
        ? state.diarySegments
        : rawDiarySegments;
    final next = state.copyWith(
      diaryStatus: diaryStatus,
      points: state.points.isEmpty && fallbackPoints.isNotEmpty
          ? fallbackPoints
          : state.points,
      segments: nextSegments,
      diarySegments: nextDiarySegments,
      distanceMeters: diary.enrichmentCompleted && diary.segments.isNotEmpty
          ? diary.movementDistanceMeters
          : state.distanceMeters,
      enrichmentPending: enrichmentPending,
      enrichmentFailed: enrichmentFailed,
      enrichmentErrorMessage: failureMessage,
      diaryError: failureMessage,
      diaryRetryPending: false,
    );
    _emitResolved(next);
    _pollPendingDiaryIfNeeded(
      tripId,
      generation,
      pending: enrichmentPending && pollPendingDiary,
    );
  }

  Future<AppResult<T>> _safeTimedFetch<T>(
    String? traceId,
    String stage,
    Future<AppResult<T>> Function() fetch, {
    Duration? timeout,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final future = fetch();
      final result = timeout == null
          ? await future
          : await future.timeout(
              timeout,
              onTimeout: () => AppResult<T>.failure(
                NetworkFailure(
                  'Richiesta scaduta dopo ${timeout.inSeconds}s',
                ),
              ),
            );
      TripDetailDiagnostics.event(
        traceId,
        '${stage}_complete',
        fields: {
          'duration_ms': stopwatch.elapsedMilliseconds,
          'success': result.failure == null,
        },
      );
      return result;
    } catch (error) {
      TripDetailDiagnostics.event(
        traceId,
        '${stage}_exception',
        fields: {
          'duration_ms': stopwatch.elapsedMilliseconds,
          'error_type': error.runtimeType,
        },
      );
      return AppResult.failure(toAppFailure(error));
    }
  }

  bool _isCurrent(int tripId, int generation) {
    return !isClosed && _tripId == tripId && _loadGeneration == generation;
  }

  void _emitResolved(TripTrackCubitState next) {
    if (isClosed) return;
    final trackDone = next.trackStatus == TrackLoadStatus.loaded ||
        next.trackStatus == TrackLoadStatus.failed;
    final diaryDone = next.diaryStatus == DiaryLoadStatus.loaded ||
        next.diaryStatus == DiaryLoadStatus.failed;

    if (next.points.isNotEmpty) {
      emit(next.copyWith(status: TripTrackStatus.loaded, error: null));
      return;
    }
    if (!trackDone || !diaryDone) {
      emit(next.copyWith(status: TripTrackStatus.loading, error: null));
      return;
    }
    if (next.trackStatus == TrackLoadStatus.failed &&
        next.diaryStatus == DiaryLoadStatus.failed) {
      emit(
        next.copyWith(
          status: TripTrackStatus.error,
          error: next.diaryError ?? next.trackError ?? 'Errore sconosciuto',
        ),
      );
      return;
    }
    emit(next.copyWith(status: TripTrackStatus.empty, error: null));
  }

  void _pollPendingDiaryIfNeeded(
    int tripId,
    int generation, {
    required bool pending,
  }) {
    if (!pending) {
      _stopDiaryPolling();
      return;
    }
    _scheduleDiaryPoll(
      tripId,
      generation,
      delay: _diaryLoadPolicy.pollingInterval,
    );
  }

  /// Polling da 1 secondo per il diario
  /// Non serve per la traccia, quando questa funzione viene eseguita, il back end ha già il trip salvato con la LineString
  void _scheduleDiaryPoll(
    int tripId,
    int generation, {
    required Duration delay,
  }) {
    _diaryPollingTimer?.cancel();
    if (isClosed) return;
    TripDetailDiagnostics.event(
      _diagnosticsTraceId,
      'diary_poll_scheduled',
      fields: {'delay_ms': delay.inMilliseconds},
    );
    _diaryPollingTimer = Timer(delay, () {
      _diaryPollingTimer = null;
      if (!_isCurrent(tripId, generation)) return;
      TripDetailDiagnostics.event(_diagnosticsTraceId, 'diary_poll_tick');
      unawaited(_loadDiary(tripId, generation, pollPendingDiary: true));
    });
  }

  String _enrichmentFailureMessage(String? reasonCode) {
    return switch (reasonCode) {
      'diary_enrichment_failed' =>
        'Non siamo riusciti ad arricchire il diario di questo viaggio.',
      _ => 'Diario non disponibile per questo viaggio.',
    };
  }

  void _stopDiaryPolling() {
    if (_diaryPollingTimer != null) {
      TripDetailDiagnostics.event(_diagnosticsTraceId, 'diary_polling_stopped');
    }
    _diaryPollingTimer?.cancel();
    _diaryPollingTimer = null;
  }

  @override
  Future<void> close() async {
    _loadGeneration += 1;
    TripDetailDiagnostics.event(_diagnosticsTraceId, 'track_cubit_closed');
    _stopDiaryPolling();
    return super.close();
  }
}

bool _sameList<T>(
  List<T> current,
  List<T> next,
  bool Function(T current, T next) sameItem,
) {
  if (identical(current, next)) return true;
  if (current.length != next.length) return false;
  for (var index = 0; index < current.length; index += 1) {
    if (!sameItem(current[index], next[index])) return false;
  }
  return true;
}

bool _sameTrackSegment(
  TripTrackSegmentState current,
  TripTrackSegmentState next,
) {
  return current.activityLabel == next.activityLabel &&
      current.distanceMeters == next.distanceMeters &&
      current.startTimestamp == next.startTimestamp &&
      current.endTimestamp == next.endTimestamp &&
      _sameList(current.points, next.points, (a, b) => a == b);
}

bool _sameDiarySegment(TripDiarySegment current, TripDiarySegment next) {
  return current.segmentKind == next.segmentKind &&
      current.startTimestamp == next.startTimestamp &&
      current.endTimestamp == next.endTimestamp &&
      current.activity == next.activity &&
      current.distanceMeters == next.distanceMeters &&
      current.place?.id == next.place?.id &&
      _sameList(current.points, next.points, (a, b) => a == b);
}
