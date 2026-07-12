import 'dart:async';

import 'package:diary/repositories/trip_track_repository.dart';
import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class TripTrackCubit extends Cubit<TripTrackCubitState> {
  static const _diaryPollingInterval = Duration(seconds: 1);

  final TripTrackRepository _repository;
  Timer? _diaryPollingTimer;
  int? _tripId;
  bool _isPollingDiary = false;

  TripTrackCubit(this._repository) : super(const TripTrackCubitState.initial());

  Future<void> load(int tripId) async {
    _tripId = tripId;
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
    final previousState = state;
    if (showLoading) {
      emit(const TripTrackCubitState(status: TripTrackStatus.loading));
    }
    try {
      final diaryResult = await _repository.fetchDiary(tripId);
      final diaryFailure = diaryResult.failure;
      if (diaryFailure != null) {
        throw diaryFailure;
      }
      final diary = diaryResult.requireValue;
      final enrichmentFailed = !diary.processed && diary.enrichmentFailed;
      final enrichmentPending = !diary.processed && !enrichmentFailed;
      final enrichmentErrorMessage = enrichmentFailed
          ? _enrichmentFailureMessage(diary.enrichmentFailureReason)
          : null;
      final drawableSegments = diary.drawableSegments;
      if (diary.processed && drawableSegments.isNotEmpty) {
        _pollPendingDiaryIfNeeded(tripId, pending: false);
        final segments = [
          for (final segment in drawableSegments)
            TripTrackSegmentState(
              points: segment.points,
              activityLabel: segment.activityLabel,
              distanceMeters: segment.distanceMeters,
              startTimestamp: segment.startTimestamp,
              endTimestamp: segment.endTimestamp,
            ),
        ];
        final points = [
          for (final segment in segments) ...segment.points,
        ];
        emit(
          TripTrackCubitState(
            status: TripTrackStatus.loaded,
            points: points,
            segments: segments,
            diarySegments: diary.segments,
            distanceMeters: diary.movementDistanceMeters,
            enrichmentPending: false,
            enrichmentFailed: false,
          ),
        );
        return;
      }

      final trackResult = await _repository.fetchTrack(tripId);
      final trackFailure = trackResult.failure;
      if (trackFailure != null) {
        throw trackFailure;
      }
      final track = trackResult.requireValue;
      final points = track.points;
      emit(
        TripTrackCubitState(
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
      _pollPendingDiaryIfNeeded(
        tripId,
        pending: enrichmentPending && pollPendingDiary,
      );
    } catch (error) {
      emit(
        TripTrackCubitState(
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

  void _pollPendingDiaryIfNeeded(int tripId, {required bool pending}) {
    if (!pending) {
      _stopDiaryPolling();
      return;
    }
    if (_diaryPollingTimer != null) return;

    _diaryPollingTimer = Timer.periodic(_diaryPollingInterval, (_) {
      if (_isPollingDiary || isClosed) return;
      _isPollingDiary = true;
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
    _diaryPollingTimer?.cancel();
    _diaryPollingTimer = null;
  }

  @override
  Future<void> close() async {
    _stopDiaryPolling();
    return super.close();
  }
}
