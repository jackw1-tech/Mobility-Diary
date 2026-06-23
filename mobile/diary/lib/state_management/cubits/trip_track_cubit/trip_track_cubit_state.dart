import 'package:diary/network/dto/trip_track_dto.dart';
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
  final List<TripDiarySegmentDto> diarySegments;
  final double distanceMeters;
  final bool enrichmentPending;
  final String? error;

  const TripTrackCubitState({
    required this.status,
    this.points = const [],
    this.segments = const [],
    this.diarySegments = const [],
    this.distanceMeters = 0,
    this.enrichmentPending = false,
    this.error,
  });

  const TripTrackCubitState.initial()
      : status = TripTrackStatus.initial,
        points = const [],
        segments = const [],
        diarySegments = const [],
        distanceMeters = 0,
        enrichmentPending = false,
        error = null;

  bool get isLoading => status == TripTrackStatus.loading;
  bool get isSegmented => segments.isNotEmpty;
}

class TripTrackSegmentState {
  final List<LatLng> points;
  final String activityLabel;
  final double distanceMeters;

  const TripTrackSegmentState({
    required this.points,
    required this.activityLabel,
    required this.distanceMeters,
  });
}
