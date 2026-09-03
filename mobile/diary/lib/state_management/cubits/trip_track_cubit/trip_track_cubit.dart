import 'dart:async';

import 'package:diary/model/entities/trips/trip_track.dart';
import 'package:diary/repositories/trip_track_repository.dart';
import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit_state.dart';
import 'package:diary/utils/app_result.dart';
import 'package:diary/utils/trip_detail_diagnostics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class TripTrackCubit extends Cubit<TripTrackCubitState> {
  static const _defaultDiaryPollingInterval = Duration(seconds: 1);
  static const _defaultDiaryRequestTimeout = Duration(seconds: 20);
  static const _defaultDiaryRetryBaseDelay = Duration(seconds: 2);
  static const _defaultDiaryRetryMaxDelay = Duration(seconds: 30);

  final TripTrackRepository _repository;
  final Duration _diaryPollingInterval;
  final Duration _diaryRequestTimeout;
  final Duration _diaryRetryBaseDelay;
  final Duration _diaryRetryMaxDelay;
  final Map<int, TripTrack> _trackCache = {};
  Timer? _diaryPollingTimer;
  int? _tripId;
  String? _diagnosticsTraceId;
  int _loadGeneration = 0;
  int _diaryFailureStreak = 0;

  TripTrackCubit(
    this._repository, {
    Duration diaryPollingInterval = _defaultDiaryPollingInterval,
    Duration diaryRequestTimeout = _defaultDiaryRequestTimeout,
    Duration diaryRetryBaseDelay = _defaultDiaryRetryBaseDelay,
    Duration diaryRetryMaxDelay = _defaultDiaryRetryMaxDelay,
  })  : _diaryPollingInterval = diaryPollingInterval,
        _diaryRequestTimeout = diaryRequestTimeout,
        _diaryRetryBaseDelay = diaryRetryBaseDelay,
        _diaryRetryMaxDelay = diaryRetryMaxDelay,
        super(const TripTrackCubitState.initial());

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

  Future<void> _startLoad(int tripId) async {
    final generation = ++_loadGeneration;
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
      timeout: _diaryRequestTimeout,
    );
    if (!_isCurrent(tripId, generation)) return;

    final failure = result.failure;
    if (failure != null) {
      // Un errore di trasporto non dice nulla sull'arricchimento: si continua
      // a interrogare il diario con backoff invece di dichiarare fallito
      // l'HAR e spegnere il polling per sempre.
      _diaryFailureStreak += 1;
      final retryDelay = _diaryRetryDelay(_diaryFailureStreak);
      final keepsPreviousDiary =
          state.diaryStatus == DiaryLoadStatus.loaded ||
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
        'processed': diary.processed,
        'segment_count': diary.segments.length,
        'place_count': diary.places.length,
        'generation': generation,
      },
    );
    final enrichmentFailed = !diary.processed && diary.enrichmentFailed;
    final enrichmentPending = !diary.processed && !enrichmentFailed;
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
    final nextSegments = _sameTrackSegments(state.segments, segments)
        ? state.segments
        : segments;
    final rawDiarySegments =
        diary.processed ? diary.segments : const <TripDiarySegment>[];
    final nextDiarySegments =
        _sameDiarySegments(state.diarySegments, rawDiarySegments)
            ? state.diarySegments
            : rawDiarySegments;
    final next = state.copyWith(
      diaryStatus: diaryStatus,
      points: state.points.isEmpty && fallbackPoints.isNotEmpty
          ? fallbackPoints
          : state.points,
      segments: nextSegments,
      diarySegments: nextDiarySegments,
      distanceMeters: diary.processed && diary.segments.isNotEmpty
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
    _scheduleDiaryPoll(tripId, generation, delay: _diaryPollingInterval);
  }

  /// Un solo timer alla volta, riarmato dopo ogni tentativo concluso: senza
  /// timer periodico non esiste piu' un tick che possa sovrapporsi a una
  /// richiesta in volo ne' un latch da sbloccare.
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

  Duration _diaryRetryDelay(int failureStreak) {
    final multiplier = 1 << (failureStreak - 1).clamp(0, 10);
    final delay = _diaryRetryBaseDelay * multiplier;
    return delay > _diaryRetryMaxDelay ? _diaryRetryMaxDelay : delay;
  }

  bool _sameTrackSegments(
    List<TripTrackSegmentState> current,
    List<TripTrackSegmentState> next,
  ) {
    if (identical(current, next)) return true;
    if (current.length != next.length) return false;
    for (var index = 0; index < current.length; index += 1) {
      final a = current[index];
      final b = next[index];
      if (a.activityLabel != b.activityLabel ||
          a.distanceMeters != b.distanceMeters ||
          a.startTimestamp != b.startTimestamp ||
          a.endTimestamp != b.endTimestamp ||
          a.points.length != b.points.length) {
        return false;
      }
      for (var point = 0; point < a.points.length; point += 1) {
        if (a.points[point] != b.points[point]) return false;
      }
    }
    return true;
  }

  bool _sameDiarySegments(
    List<TripDiarySegment> current,
    List<TripDiarySegment> next,
  ) {
    if (identical(current, next)) return true;
    if (current.length != next.length) return false;
    for (var index = 0; index < current.length; index += 1) {
      final a = current[index];
      final b = next[index];
      if (a.segmentKind != b.segmentKind ||
          a.startTimestamp != b.startTimestamp ||
          a.endTimestamp != b.endTimestamp ||
          a.activity != b.activity ||
          a.distanceMeters != b.distanceMeters ||
          a.place?.id != b.place?.id ||
          a.points.length != b.points.length) {
        return false;
      }
    }
    return true;
  }

  String _enrichmentFailureMessage(String? reasonCode) {
    return switch (reasonCode) {
      'diary_enrichment_failed' =>
        'Non siamo riusciti a elaborare il diario di questo viaggio.',
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
