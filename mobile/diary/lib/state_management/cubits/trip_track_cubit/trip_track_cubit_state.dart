import 'package:diary/model/entities/trips/trip_track.dart';
import 'package:latlong2/latlong.dart';

const _notProvided = Object();

enum TripTrackStatus {
  initial,
  loading,
  loaded,
  empty,
  error,
}

enum TrackLoadStatus { initial, loading, loaded, failed }

enum DiaryLoadStatus { initial, loading, pending, loaded, failed }

class TripTrackCubitState {
  final int? tripId;
  final String? diagnosticsTraceId;
  final TripTrackStatus status;
  final TrackLoadStatus trackStatus;
  final DiaryLoadStatus diaryStatus;
  final List<LatLng> points;
  final List<TripTrackSegmentState> segments;
  final List<TripDiarySegment> diarySegments;
  final double distanceMeters;
  final bool enrichmentPending;
  final bool enrichmentFailed;
  /// Il diario non e' arrivato per un errore di trasporto e un nuovo
  /// tentativo e' gia' programmato: distingue l'attesa dal fallimento
  /// definitivo dell'arricchimento.
  final bool diaryRetryPending;
  final String? enrichmentErrorMessage;
  final String? trackError;
  final String? diaryError;
  final String? error;

  const TripTrackCubitState({
    required this.status,
    this.trackStatus = TrackLoadStatus.initial,
    this.diaryStatus = DiaryLoadStatus.initial,
    this.tripId,
    this.diagnosticsTraceId,
    this.points = const [],
    this.segments = const [],
    this.diarySegments = const [],
    this.distanceMeters = 0,
    this.enrichmentPending = false,
    this.enrichmentFailed = false,
    this.diaryRetryPending = false,
    this.enrichmentErrorMessage,
    this.trackError,
    this.diaryError,
    this.error,
  });

  const TripTrackCubitState.initial()
      : tripId = null,
        diagnosticsTraceId = null,
        status = TripTrackStatus.initial,
        trackStatus = TrackLoadStatus.initial,
        diaryStatus = DiaryLoadStatus.initial,
        points = const [],
        segments = const [],
        diarySegments = const [],
        distanceMeters = 0,
        enrichmentPending = false,
        enrichmentFailed = false,
        diaryRetryPending = false,
        enrichmentErrorMessage = null,
        trackError = null,
        diaryError = null,
        error = null;

  bool get isLoading => status == TripTrackStatus.loading;
  bool get isSegmented => segments.isNotEmpty;

  TripTrackCubitState copyWith({
    TripTrackStatus? status,
    TrackLoadStatus? trackStatus,
    DiaryLoadStatus? diaryStatus,
    List<LatLng>? points,
    List<TripTrackSegmentState>? segments,
    List<TripDiarySegment>? diarySegments,
    double? distanceMeters,
    bool? enrichmentPending,
    bool? enrichmentFailed,
    bool? diaryRetryPending,
    Object? enrichmentErrorMessage = _notProvided,
    Object? trackError = _notProvided,
    Object? diaryError = _notProvided,
    Object? error = _notProvided,
  }) {
    return TripTrackCubitState(
      tripId: tripId,
      diagnosticsTraceId: diagnosticsTraceId,
      status: status ?? this.status,
      trackStatus: trackStatus ?? this.trackStatus,
      diaryStatus: diaryStatus ?? this.diaryStatus,
      points: points ?? this.points,
      segments: segments ?? this.segments,
      diarySegments: diarySegments ?? this.diarySegments,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      enrichmentPending: enrichmentPending ?? this.enrichmentPending,
      enrichmentFailed: enrichmentFailed ?? this.enrichmentFailed,
      diaryRetryPending: diaryRetryPending ?? this.diaryRetryPending,
      enrichmentErrorMessage: identical(enrichmentErrorMessage, _notProvided)
          ? this.enrichmentErrorMessage
          : enrichmentErrorMessage as String?,
      trackError: identical(trackError, _notProvided)
          ? this.trackError
          : trackError as String?,
      diaryError: identical(diaryError, _notProvided)
          ? this.diaryError
          : diaryError as String?,
      error: identical(error, _notProvided) ? this.error : error as String?,
    );
  }
}

class TripTrackSegmentState {
  final List<LatLng> points;
  final String activityLabel;
  final double distanceMeters;
  final DateTime startTimestamp;
  final DateTime endTimestamp;

  const TripTrackSegmentState({
    required this.points,
    required this.activityLabel,
    required this.distanceMeters,
    required this.startTimestamp,
    required this.endTimestamp,
  });
}
