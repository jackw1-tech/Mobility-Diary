import 'dart:async';

import 'package:diary/network/service/trip_track_service.dart';
import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class TripTrackCubit extends Cubit<TripTrackCubitState> {
  final TripTrackService _service;
  final Duration _pollDelay;
  final int _maxPendingPolls;
  Timer? _pendingPollTimer;
  int _pendingPolls = 0;

  TripTrackCubit(
    this._service, {
    Duration pollDelay = const Duration(seconds: 15),
    int maxPendingPolls = 20,
  })  : _pollDelay = pollDelay,
        _maxPendingPolls = maxPendingPolls,
        super(const TripTrackCubitState.initial());

  Future<void> load(int tripId) async {
    _pendingPollTimer?.cancel();
    _pendingPolls = 0;
    await _load(tripId, showLoading: true);
  }

  Future<void> _load(int tripId, {required bool showLoading}) async {
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
            distanceMeters: track.distanceMeters,
            enrichmentPending: !diary.processed,
          ),
        );
        _schedulePendingPoll(tripId, pending: !diary.processed);
        return;
      }

      emit(
        TripTrackCubitState(
          status: TripTrackStatus.loaded,
          points: points,
          distanceMeters: track.distanceMeters,
          enrichmentPending: !diary.processed,
        ),
      );
      _schedulePendingPoll(tripId, pending: !diary.processed);
    } catch (error) {
      emit(
        TripTrackCubitState(
          status: TripTrackStatus.error,
          error: error.toString(),
        ),
      );
    }
  }

  void _schedulePendingPoll(int tripId, {required bool pending}) {
    _pendingPollTimer?.cancel();
    if (!pending || _pendingPolls >= _maxPendingPolls) return;
    _pendingPolls += 1;
    _pendingPollTimer = Timer(_pollDelay, () {
      if (isClosed) return;
      _load(tripId, showLoading: false);
    });
  }

  @override
  Future<void> close() {
    _pendingPollTimer?.cancel();
    return super.close();
  }
}
