import 'package:diary/model/entities/trips/trip_track.dart';
import 'package:latlong2/latlong.dart';

const _notProvided = Object();

enum TripTrackStatus { initial, loading, loaded, empty, error }

enum TrackLoadStatus { initial, loading, loaded, failed }

enum DiaryLoadStatus { initial, loading, pending, loaded, failed }

class TripTrackCubitState {
  final int? tripId;
  final TripTrackStatus status;
  final TrackLoadStatus trackStatus;
  final DiaryLoadStatus diaryStatus;
  final List<LatLng> points;
  final List<TripTrackSegmentState> segments;
  final List<TripDiarySegment> diarySegments;
  final double distanceMeters;
  // Distanza dell'intero percorso (dalla prima GET del track), mai
  // sovrascritta dal diario: usata per la tab Statistiche, a differenza di
  // [distanceMeters] che invece diventa la somma dei soli segmenti di
  // movimento una volta che il diario e' caricato (usata nella tab Mappa).
  final double trackDistanceMeters;
  final bool processingPending;
  final bool processingFailed;

  final bool diaryRetryPending;
  final String? processingErrorMessage;
  final String? trackError;
  final String? diaryError;
  final String? error;

  const TripTrackCubitState({
    required this.status,
    this.trackStatus = TrackLoadStatus.initial,
    this.diaryStatus = DiaryLoadStatus.initial,
    this.tripId,
    this.points = const [],
    this.segments = const [],
    this.diarySegments = const [],
    this.distanceMeters = 0,
    this.trackDistanceMeters = 0,
    this.processingPending = false,
    this.processingFailed = false,
    this.diaryRetryPending = false,
    this.processingErrorMessage,
    this.trackError,
    this.diaryError,
    this.error,
  });

  const TripTrackCubitState.initial()
    : tripId = null,
      status = TripTrackStatus.initial,
      trackStatus = TrackLoadStatus.initial,
      diaryStatus = DiaryLoadStatus.initial,
      points = const [],
      segments = const [],
      diarySegments = const [],
      distanceMeters = 0,
      trackDistanceMeters = 0,
      processingPending = false,
      processingFailed = false,
      diaryRetryPending = false,
      processingErrorMessage = null,
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
    double? trackDistanceMeters,
    bool? processingPending,
    bool? processingFailed,
    bool? diaryRetryPending,
    Object? processingErrorMessage = _notProvided,
    Object? trackError = _notProvided,
    Object? diaryError = _notProvided,
    Object? error = _notProvided,
  }) {
    return TripTrackCubitState(
      tripId: tripId,
      status: status ?? this.status,
      trackStatus: trackStatus ?? this.trackStatus,
      diaryStatus: diaryStatus ?? this.diaryStatus,
      points: points ?? this.points,
      segments: segments ?? this.segments,
      diarySegments: diarySegments ?? this.diarySegments,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      trackDistanceMeters: trackDistanceMeters ?? this.trackDistanceMeters,
      processingPending: processingPending ?? this.processingPending,
      processingFailed: processingFailed ?? this.processingFailed,
      diaryRetryPending: diaryRetryPending ?? this.diaryRetryPending,
      processingErrorMessage: identical(processingErrorMessage, _notProvided)
          ? this.processingErrorMessage
          : processingErrorMessage as String?,
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
