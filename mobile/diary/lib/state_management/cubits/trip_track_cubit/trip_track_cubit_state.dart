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
  final double distanceMeters;
  final String? error;

  const TripTrackCubitState({
    required this.status,
    this.points = const [],
    this.distanceMeters = 0,
    this.error,
  });

  const TripTrackCubitState.initial()
      : status = TripTrackStatus.initial,
        points = const [],
        distanceMeters = 0,
        error = null;

  bool get isLoading => status == TripTrackStatus.loading;
}
