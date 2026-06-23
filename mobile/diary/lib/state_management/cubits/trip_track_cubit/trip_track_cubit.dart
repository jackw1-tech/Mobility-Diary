import 'dart:async';

import 'package:diary/network/service/trip_track_service.dart';
import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class TripTrackCubit extends Cubit<TripTrackCubitState> {
  final TripTrackService _service;
  StreamSubscription<String>? _diaryEventSubscription;
  int? _tripId;

  TripTrackCubit(this._service) : super(const TripTrackCubitState.initial());

  Future<void> load(int tripId) async {
    _tripId = tripId;
    await _diaryEventSubscription?.cancel();
    _diaryEventSubscription = null;
    await _load(tripId, showLoading: true, watchPendingDiary: true);
  }

  Future<void> reload() async {
    final tripId = _tripId;
    if (tripId == null) return;
    await load(tripId);
  }

  Future<void> _load(
    int tripId, {
    required bool showLoading,
    required bool watchPendingDiary,
  }) async {
    final previousState = state;
    if (showLoading) {
      emit(const TripTrackCubitState(status: TripTrackStatus.loading));
    }
    try {
      final diary = await _service.fetchDiary(tripId);
      final drawableSegments = diary.drawableSegments;
      if (diary.processed && drawableSegments.isNotEmpty) {
        final segments = [
          for (final segment in drawableSegments)
            TripTrackSegmentState(
              points: segment.points,
              activityLabel: segment.activityLabel,
              distanceMeters: segment.distanceMeters,
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
          ),
        );
        return;
      }

      final track = await _service.fetchTrack(tripId);
      final points = track.points;
      if (points.isEmpty) {
        emit(
          TripTrackCubitState(
            status: TripTrackStatus.empty,
            diarySegments: diary.processed ? diary.segments : const [],
            distanceMeters: track.distanceMeters,
            enrichmentPending: !diary.processed,
          ),
        );
        _watchPendingDiaryIfNeeded(
          tripId,
          pending: !diary.processed && watchPendingDiary,
        );
        return;
      }

      emit(
        TripTrackCubitState(
          status: TripTrackStatus.loaded,
          points: points,
          diarySegments: diary.processed ? diary.segments : const [],
          distanceMeters: track.distanceMeters,
          enrichmentPending: !diary.processed,
        ),
      );
      _watchPendingDiaryIfNeeded(
        tripId,
        pending: !diary.processed && watchPendingDiary,
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
          error: error.toString(),
        ),
      );
    }
  }

  void _watchPendingDiaryIfNeeded(int tripId, {required bool pending}) {
    if (!pending) {
      unawaited(_diaryEventSubscription?.cancel());
      _diaryEventSubscription = null;
      return;
    }
    if (_diaryEventSubscription != null) return;

    _diaryEventSubscription = _service.watchDiaryEvents(tripId).listen(
      (event) {
        if (event != 'diary_enriched') return;
        unawaited(_refreshAfterDiaryEvent(tripId));
      },
      onError: (_) {},
    );
  }

  Future<void> _refreshAfterDiaryEvent(int tripId) async {
    await _diaryEventSubscription?.cancel();
    _diaryEventSubscription = null;
    if (isClosed) return;
    await _load(tripId, showLoading: false, watchPendingDiary: false);
  }

  @override
  Future<void> close() async {
    await _diaryEventSubscription?.cancel();
    return super.close();
  }
}
