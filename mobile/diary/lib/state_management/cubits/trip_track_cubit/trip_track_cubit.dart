import 'dart:async';

import 'package:diary/model/entities/trips/trip_track.dart';
import 'package:diary/repositories/trip_track_repository.dart';
import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit_state.dart';
import 'package:diary/utils/app_result.dart';
import 'package:diary/utils/trip_detail_diagnostics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';

class TripTrackCubit extends Cubit<TripTrackCubitState> {
  static const _diaryPollingInterval = Duration(seconds: 1);

  final TripTrackRepository _repository;
  Timer? _diaryPollingTimer;
  int? _tripId;
  String? _diagnosticsTraceId;
  bool _isPollingDiary = false;

  TripTrackCubit(this._repository) : super(const TripTrackCubitState.initial());

  Future<void> load(int tripId, {String? diagnosticsTraceId}) async {
    _tripId = tripId;
    _diagnosticsTraceId = diagnosticsTraceId;
    _stopDiaryPolling();
    await _load(tripId, showLoading: true, pollPendingDiary: true);
  }

  Future<void> reload() async {
    final tripId = _tripId;
    if (tripId == null) return;
    await _load(
      tripId,
      showLoading: true,
      pollPendingDiary: true,
    );
  }

  Future<void> _load(
    int tripId, {
    required bool showLoading,
    required bool pollPendingDiary,
  }) async {
    final traceId = _diagnosticsTraceId;
    final totalWatch = Stopwatch()..start();
    TripDetailDiagnostics.event(
      traceId,
      'track_cubit_load_start',
      fields: {
        'show_loading': showLoading,
        'poll_pending': pollPendingDiary,
      },
    );
    final previousState = state;
    if (showLoading) {
      emit(
        TripTrackCubitState(
          tripId: tripId,
          diagnosticsTraceId: traceId,
          status: TripTrackStatus.loading,
        ),
      );
      TripDetailDiagnostics.event(traceId, 'track_state_loading_emitted');
    }
    try {
      // diary e track sono richieste indipendenti, servono entrambe in ogni
      // ramo sotto: partono insieme invece che una dopo l'altra, dimezzando
      // il tempo di attesa di rete (il caso comune, viaggio gia' processato).
      final diaryFuture = _timedFetch(
        traceId,
        'diary_repository_future',
        () => _repository.fetchDiary(tripId),
      );
      final trackFuture = _timedFetch(
        traceId,
        'track_repository_future',
        () => _repository.fetchTrack(tripId),
      );
      TripDetailDiagnostics.event(traceId, 'parallel_requests_started');
      final diaryResult = await diaryFuture;
      final diaryFailure = diaryResult.failure;
      if (diaryFailure != null) {
        throw diaryFailure;
      }
      final diary = diaryResult.requireValue;
      TripDetailDiagnostics.event(
        traceId,
        'diary_result_available',
        fields: {
          'processed': diary.processed,
          'segment_count': diary.segments.length,
          'place_count': diary.places.length,
        },
      );
      final enrichmentFailed = !diary.processed && diary.enrichmentFailed;
      final enrichmentPending = !diary.processed && !enrichmentFailed;
      final enrichmentErrorMessage = enrichmentFailed
          ? _enrichmentFailureMessage(diary.enrichmentFailureReason)
          : null;
      final drawableWatch = Stopwatch()..start();
      final drawableSegments = diary.drawableSegments;
      TripDetailDiagnostics.event(
        traceId,
        'diary_drawable_segments_computed',
        fields: {
          'duration_ms': drawableWatch.elapsedMilliseconds,
          'drawable_count': drawableSegments.length,
        },
      );
      if (diary.processed && drawableSegments.isNotEmpty) {
        _pollPendingDiaryIfNeeded(tripId, pending: false);
        final segmentMapWatch = Stopwatch()..start();
        var segmentPointCount = 0;
        final segments = <TripTrackSegmentState>[];
        for (final segment in drawableSegments) {
          final points = segment.points;
          segmentPointCount += points.length;
          segments.add(
            TripTrackSegmentState(
              points: points,
              activityLabel: segment.activityLabel,
              distanceMeters: segment.distanceMeters,
              startTimestamp: segment.startTimestamp,
              endTimestamp: segment.endTimestamp,
            ),
          );
        }
        TripDetailDiagnostics.event(
          traceId,
          'diary_segments_mapped_to_points',
          fields: {
            'duration_ms': segmentMapWatch.elapsedMilliseconds,
            'segment_count': segments.length,
            'segment_point_count': segmentPointCount,
          },
        );
        // La traccia grezza serve comunque: e' quella che la vista "Traccia"
        // mostra, ed e' l'unico modo di vedere i fix GPS che restano fuori
        // dalle finestre temporali dei segmenti. Se non arriva, si ripiega
        // sulla concatenazione dei segmenti.
        final rawTrackWatch = Stopwatch()..start();
        final points = await _rawTrackPointsFrom(trackFuture) ??
            [
              for (final segment in segments) ...segment.points,
            ];
        TripDetailDiagnostics.event(
          traceId,
          'raw_track_points_ready',
          fields: {
            'duration_ms': rawTrackWatch.elapsedMilliseconds,
            'point_count': points.length,
          },
        );
        emit(
          TripTrackCubitState(
            tripId: tripId,
            diagnosticsTraceId: traceId,
            status: TripTrackStatus.loaded,
            points: points,
            segments: segments,
            diarySegments: diary.segments,
            distanceMeters: diary.movementDistanceMeters,
            enrichmentPending: false,
            enrichmentFailed: false,
          ),
        );
        TripDetailDiagnostics.event(
          traceId,
          'track_state_loaded_emitted',
          fields: {
            'total_duration_ms': totalWatch.elapsedMilliseconds,
            'point_count': points.length,
            'segment_count': segments.length,
            'diary_segment_count': diary.segments.length,
          },
        );
        return;
      }

      final trackResult = await trackFuture;
      final trackFailure = trackResult.failure;
      if (trackFailure != null) {
        throw trackFailure;
      }
      final track = trackResult.requireValue;
      final trackPointsWatch = Stopwatch()..start();
      final points = track.points;
      TripDetailDiagnostics.event(
        traceId,
        'fallback_track_points_parsed',
        fields: {
          'duration_ms': trackPointsWatch.elapsedMilliseconds,
          'point_count': points.length,
        },
      );
      emit(
        TripTrackCubitState(
          tripId: tripId,
          diagnosticsTraceId: traceId,
          status:
              points.isEmpty ? TripTrackStatus.empty : TripTrackStatus.loaded,
          points: points,
          diarySegments: diary.processed ? diary.segments : const [],
          distanceMeters: track.distanceMeters,
          enrichmentPending: enrichmentPending,
          enrichmentFailed: enrichmentFailed,
          enrichmentErrorMessage: enrichmentErrorMessage,
        ),
      );
      TripDetailDiagnostics.event(
        traceId,
        'track_state_fallback_emitted',
        fields: {
          'total_duration_ms': totalWatch.elapsedMilliseconds,
          'status': points.isEmpty ? 'empty' : 'loaded',
          'point_count': points.length,
          'enrichment_pending': enrichmentPending,
        },
      );
      _pollPendingDiaryIfNeeded(
        tripId,
        pending: enrichmentPending && pollPendingDiary,
      );
    } catch (error) {
      TripDetailDiagnostics.event(
        traceId,
        'track_cubit_load_error',
        fields: {
          'total_duration_ms': totalWatch.elapsedMilliseconds,
          'error_type': error.runtimeType,
        },
      );
      emit(
        TripTrackCubitState(
          tripId: tripId,
          diagnosticsTraceId: traceId,
          status: TripTrackStatus.error,
          points: previousState.points,
          segments: previousState.segments,
          diarySegments: previousState.diarySegments,
          distanceMeters: previousState.distanceMeters,
          enrichmentPending: previousState.enrichmentPending,
          enrichmentFailed: previousState.enrichmentFailed,
          enrichmentErrorMessage: previousState.enrichmentErrorMessage,
          error: error.toString(),
        ),
      );
    }
  }

  Future<AppResult<T>> _timedFetch<T>(
    String? traceId,
    String stage,
    Future<AppResult<T>> Function() fetch,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      final result = await fetch();
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
      rethrow;
    }
  }

  /// Punti della traccia grezza da una richiesta gia' in volo, o `null` se
  /// non recuperabili: un viaggio con il diario gia' pronto resta
  /// visualizzabile anche se questa richiesta fallisce.
  Future<List<LatLng>?> _rawTrackPointsFrom(
    Future<AppResult<TripTrack>> trackFuture,
  ) async {
    final result = await trackFuture;
    if (result.failure != null) {
      return null;
    }
    final points = result.requireValue.points;
    return points.isEmpty ? null : points;
  }

  void _pollPendingDiaryIfNeeded(int tripId, {required bool pending}) {
    if (!pending) {
      _stopDiaryPolling();
      return;
    }
    if (_diaryPollingTimer != null) return;

    TripDetailDiagnostics.event(
      _diagnosticsTraceId,
      'diary_polling_started',
      fields: {'interval_ms': _diaryPollingInterval.inMilliseconds},
    );

    _diaryPollingTimer = Timer.periodic(_diaryPollingInterval, (_) {
      if (_isPollingDiary || isClosed) return;
      _isPollingDiary = true;
      TripDetailDiagnostics.event(_diagnosticsTraceId, 'diary_poll_tick');
      unawaited(
        _load(tripId, showLoading: false, pollPendingDiary: true)
            .whenComplete(() => _isPollingDiary = false),
      );
    });
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
    TripDetailDiagnostics.event(_diagnosticsTraceId, 'track_cubit_closed');
    _stopDiaryPolling();
    return super.close();
  }
}
