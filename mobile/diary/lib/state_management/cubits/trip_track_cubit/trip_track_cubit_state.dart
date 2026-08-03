import 'package:diary/model/entities/trips/trip_track.dart';
import 'package:latlong2/latlong.dart';

enum TripTrackStatus {
  initial,
  loading,
  loaded,
  empty,
  error,
}

class TripTrackCubitState {
  final TripTrackStatus status;
  final List<LatLng> points;
  final List<TripTrackSegmentState> segments;
  final List<TripDiarySegment> diarySegments;
  final double distanceMeters;
  final bool enrichmentPending;
  final bool enrichmentFailed;
  final String? enrichmentErrorMessage;
  final String? error;

  const TripTrackCubitState({
    required this.status,
    this.points = const [],
    this.segments = const [],
    this.diarySegments = const [],
    this.distanceMeters = 0,
    this.enrichmentPending = false,
    this.enrichmentFailed = false,
    this.enrichmentErrorMessage,
    this.error,
  });

  const TripTrackCubitState.initial()
      : status = TripTrackStatus.initial,
        points = const [],
        segments = const [],
        diarySegments = const [],
        distanceMeters = 0,
        enrichmentPending = false,
        enrichmentFailed = false,
        enrichmentErrorMessage = null,
        error = null;

  bool get isLoading => status == TripTrackStatus.loading;
  bool get isSegmented => segments.isNotEmpty;
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
