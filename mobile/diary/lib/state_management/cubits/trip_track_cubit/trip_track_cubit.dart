import 'dart:async';

import 'package:diary/model/entities/trips/trip_track.dart';
import 'package:diary/repositories/trip_track_repository.dart';
import 'package:diary/state_management/cubits/trip_track_cubit/trip_diary_load_policy.dart';
import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit_state.dart';
import 'package:diary/utils/app_result.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class TripTrackCubit extends Cubit<TripTrackCubitState> {
  final TripTrackRepository _repository;
  final TripDiaryLoadPolicy _diaryLoadPolicy;
  final Map<int, TripTrack> _trackCache = {};
  Timer? _diaryPollingTimer;
  int? _tripId;
  int _loadGeneration = 0;
  int _diaryFailureStreak = 0;

  TripTrackCubit(
    this._repository, {
    TripDiaryLoadPolicy diaryLoadPolicy = const TripDiaryLoadPolicy(),
  }) : _diaryLoadPolicy = diaryLoadPolicy,
       super(const TripTrackCubitState.initial());

  // Funzione richiamata dal cubit che chiede i dati del singolo viaggio in Trip Detail Page
  Future<void> load(int tripId) {
    _tripId = tripId;
    return _startLoad(tripId);
  }

  Future<void> reload() async {
    final tripId = _tripId;
    if (tripId == null) return;
    await _startLoad(tripId);
  }

  Future<void> retryDiaryNow() async {
    final tripId = _tripId;
    if (tripId == null) return;
    _stopDiaryPolling();
    _diaryFailureStreak = 0;
    await _loadDiary(tripId, _loadGeneration, pollPendingDiary: true);
  }

  // Fa due chiamate parallele, una per il diario e una per la traccia del viaggio
  Future<void> _startLoad(int tripId) async {
    final generation =
        ++_loadGeneration; // Protezione race condition quando cambio velocemente da un viaggio allìaltro
    _stopDiaryPolling();
    _diaryFailureStreak = 0;
    emit(
      TripTrackCubitState(
        tripId: tripId,
        status: TripTrackStatus.loading,
        trackStatus: TrackLoadStatus.loading,
        diaryStatus: DiaryLoadStatus.loading,
      ),
    );

    await Future.wait([
      _loadTrack(tripId, generation),
      _loadDiary(tripId, generation, pollPendingDiary: true),
    ]);
  }

  // Chiamo il back end e richiedo i dati del trip e il suo path (LineString -> GeoJSON)
  Future<void> _loadTrack(int tripId, int generation) async {
    final cached = _trackCache[tripId];
    final AppResult<TripTrack> result;
    if (cached != null) {
      result = AppResult.success(cached);
    } else {
      result = await _safeTimedFetch(() => _repository.fetchTrack(tripId));
    }
    if (!_isCurrent(tripId, generation)) {
      return;
    } // Protezione per scartare chiamate arrivate ma vecchie
    // Accade quando cambio velocemente da un viaggio all'altro con lo slider

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
    final diaryProvidesDistance =
        state.diaryStatus == DiaryLoadStatus.loaded &&
        state.diarySegments.isNotEmpty;
    final next = state.copyWith(
      trackStatus: TrackLoadStatus.loaded,
      points: points.isEmpty ? state.points : points,
      distanceMeters: diaryProvidesDistance
          ? state.distanceMeters
          : track.distanceMeters,
      trackDistanceMeters: track.distanceMeters,
      trackError: null,
    );
    _emitResolved(next);
  }

  // Chiamo il back end per ottenere il diario da visualizzare (diario preciso) , viene rieseguita ad ogni polling
  Future<void> _loadDiary(
    int tripId,
    int generation, {
    required bool pollPendingDiary,
  }) async {
    final result = await _safeTimedFetch(
      () => _repository.fetchDiary(tripId),
      timeout: _diaryLoadPolicy.requestTimeout,
    );
    if (!_isCurrent(tripId, generation)) return;

    final failure = result.failure;
    if (failure != null) {
      _diaryFailureStreak += 1;
      final retryDelay = _diaryLoadPolicy.retryDelay(_diaryFailureStreak);
      final keepsPreviousDiary =
          state.diaryStatus == DiaryLoadStatus.loaded ||
          state.diaryStatus == DiaryLoadStatus.pending;
      _emitResolved(
        state.copyWith(
          diaryStatus: keepsPreviousDiary
              ? state.diaryStatus
              : DiaryLoadStatus.failed,
          processingFailed: false,
          processingErrorMessage: null,
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
    final processingFailed = !diary.processed && diary.processingFailed;
    final processingPending = !diary.processed && !processingFailed;
    // Il backEnd manda solo  "segments": []
    // Il front li divide in segmenti di movimento "segment" -> andranno sulla mappa
    // e in rawDiarySegments (tutti) che andranno nella tab diario
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
    final fallbackPoints = [for (final segment in segments) ...segment.points];
    final diaryStatus = processingFailed
        ? DiaryLoadStatus.failed
        : processingPending
        ? DiaryLoadStatus.pending
        : DiaryLoadStatus.loaded;
    final failureMessage = processingFailed
        ? _processingFailureMessage(diary.processingFailureReason)
        : null;

    final nextSegments = _sameList(state.segments, segments, _sameTrackSegment)
        ? state.segments
        : segments;
    // Mostro il diario solo quando il viaggo è stato interamente processato
    final rawDiarySegments = diary.processed
        ? diary.segments
        : const <TripDiarySegment>[];
    final nextDiarySegments =
        _sameList(state.diarySegments, rawDiarySegments, _sameDiarySegment)
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
      processingPending: processingPending,
      processingFailed: processingFailed,
      processingErrorMessage: failureMessage,
      diaryError: failureMessage,
      diaryRetryPending: false,
    );
    _emitResolved(next);
    _pollPendingDiaryIfNeeded(
      tripId,
      generation,
      pending: processingPending && pollPendingDiary,
    );
  }

  Future<AppResult<T>> _safeTimedFetch<T>(
    Future<AppResult<T>> Function() fetch, {
    Duration? timeout,
  }) async {
    try {
      final future = fetch();
      final result = timeout == null
          ? await future
          : await future.timeout(
              timeout,
              onTimeout: () => AppResult<T>.failure(
                NetworkFailure('Richiesta scaduta dopo ${timeout.inSeconds}s'),
              ),
            );
      return result;
    } catch (error) {
      return AppResult.failure(toAppFailure(error));
    }
  }

  bool _isCurrent(int tripId, int generation) {
    return !isClosed && _tripId == tripId && _loadGeneration == generation;
  }

  // Funzione chiamata in modo asincrono tra loadTrack e loadDiary, in base allo stato fa aggiornare la UI
  void _emitResolved(TripTrackCubitState next) {
    if (isClosed) return;
    final trackDone =
        next.trackStatus == TrackLoadStatus.loaded ||
        next.trackStatus == TrackLoadStatus.failed;
    final diaryDone =
        next.diaryStatus == DiaryLoadStatus.loaded ||
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

  // Controlla se la fase raw è ancora pending e nel caso fa partire il polling
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
    _diaryPollingTimer = Timer(delay, () {
      _diaryPollingTimer = null;
      if (!_isCurrent(tripId, generation)) return;
      unawaited(_loadDiary(tripId, generation, pollPendingDiary: true));
    });
  }

  String _processingFailureMessage(String? reasonCode) {
    return switch (reasonCode) {
      'diary_enrichment_failed' =>
        'Non siamo riusciti a elaborare il diario di questo viaggio.',
      _ => 'Diario non disponibile per questo viaggio.',
    };
  }

  void _stopDiaryPolling() {
    _diaryPollingTimer?.cancel();
    _diaryPollingTimer = null;
  }

  @override
  Future<void> close() async {
    _loadGeneration += 1;
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
