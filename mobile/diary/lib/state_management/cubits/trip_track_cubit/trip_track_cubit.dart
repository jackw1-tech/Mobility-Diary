import 'dart:async';

import 'package:diary/features/trips/domain/diary_event.dart';
import 'package:diary/repositories/trip_track_repository.dart';
import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class TripTrackCubit extends Cubit<TripTrackCubitState> {
  final TripTrackRepository _repository;
  StreamSubscription<DiaryEvent>? _diaryEventSubscription;
  int? _tripId;
  bool _sawEnrichmentFailureThisSession = false;
  String? _enrichmentFailureReasonCode;

  TripTrackCubit(this._repository) : super(const TripTrackCubitState.initial());

  Future<void> load(int tripId) async {
    _tripId = tripId;
    _clearEnrichmentFailure();
    await _diaryEventSubscription?.cancel();
    _diaryEventSubscription = null;
    await _load(tripId, showLoading: true, watchPendingDiary: true);
  }

  Future<void> reload() async {
    final tripId = _tripId;
    if (tripId == null) return;
    await _load(
      tripId,
      showLoading: true,
      watchPendingDiary: !_sawEnrichmentFailureThisSession,
    );
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
      final diaryResult = await _repository.fetchDiary(tripId);
      final diaryFailure = diaryResult.failure;
      if (diaryFailure != null) {
        throw diaryFailure;
      }
      final diary = diaryResult.requireValue;
      if (diary.processed) _clearEnrichmentFailure();
      final enrichmentFailed =
          !diary.processed && _sawEnrichmentFailureThisSession;
      final enrichmentPending = !diary.processed && !enrichmentFailed;
      final enrichmentErrorMessage = enrichmentFailed
          ? _enrichmentFailureMessage(_enrichmentFailureReasonCode)
          : null;
      final drawableSegments = diary.drawableSegments;
      if (diary.processed && drawableSegments.isNotEmpty) {
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
      _watchPendingDiaryIfNeeded(
        tripId,
        pending: enrichmentPending && watchPendingDiary,
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

  void _watchPendingDiaryIfNeeded(int tripId, {required bool pending}) {
    if (!pending) {
      unawaited(_diaryEventSubscription?.cancel());
      _diaryEventSubscription = null;
      return;
    }
    if (_diaryEventSubscription != null) return;

    late final StreamSubscription<DiaryEvent> subscription;
    subscription = _repository.watchDiaryEvents(tripId).listen(
      (event) {
        if (event.tripId != null && event.tripId != tripId) return;
        if (event.status == DiaryEventStatus.enriched) {
          unawaited(_refreshAfterDiaryEvent(tripId));
        } else if (event.status == DiaryEventStatus.failed) {
          _handleDiaryFailure(event.reasonCode);
        }
      },
      // Lo stream si chiude da solo dopo `: timeout` (300s senza eventi) o un
      // errore di rete: azzeriamo la subscription cosi' che un successivo
      // reload()/re-watch non resti bloccato dalla guardia `!= null`.
      onError: (_) => _clearDiaryEventSubscription(subscription),
      onDone: () => _clearDiaryEventSubscription(subscription),
    );
    _diaryEventSubscription = subscription;
  }

  void _clearDiaryEventSubscription(
      StreamSubscription<DiaryEvent> subscription) {
    if (!identical(_diaryEventSubscription, subscription)) return;
    _diaryEventSubscription = null;
  }

  Future<void> _refreshAfterDiaryEvent(int tripId) async {
    await _diaryEventSubscription?.cancel();
    _diaryEventSubscription = null;
    _clearEnrichmentFailure();
    if (isClosed) return;
    await _load(tripId, showLoading: false, watchPendingDiary: false);
  }

  void _handleDiaryFailure(String? reasonCode) {
    _sawEnrichmentFailureThisSession = true;
    _enrichmentFailureReasonCode = reasonCode;
    unawaited(_diaryEventSubscription?.cancel());
    _diaryEventSubscription = null;
    if (isClosed) return;
    emit(
      TripTrackCubitState(
        status: state.status,
        points: state.points,
        segments: state.segments,
        diarySegments: state.diarySegments,
        distanceMeters: state.distanceMeters,
        enrichmentPending: false,
        enrichmentFailed: true,
        enrichmentErrorMessage: _enrichmentFailureMessage(reasonCode),
        error: state.error,
      ),
    );
  }

  String _enrichmentFailureMessage(String? reasonCode) {
    return switch (reasonCode) {
      'diary_enrichment_failed' =>
        'Non siamo riusciti a elaborare il diario di questo viaggio.',
      _ => 'Diario non disponibile per questo viaggio.',
    };
  }

  void _clearEnrichmentFailure() {
    _sawEnrichmentFailureThisSession = false;
    _enrichmentFailureReasonCode = null;
  }

  @override
  Future<void> close() async {
    await _diaryEventSubscription?.cancel();
    return super.close();
  }
}
