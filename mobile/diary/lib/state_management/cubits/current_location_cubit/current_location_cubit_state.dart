import 'package:latlong2/latlong.dart' as ll;

enum CurrentLocationStatus {
  initial,
  loading,
  loaded,
  error,
}

class CurrentLocationCubitState {
  final CurrentLocationStatus status;
  final ll.LatLng? location;
  final String? error;

  const CurrentLocationCubitState({
    required this.status,
    this.location,
    this.error,
  });

  const CurrentLocationCubitState.initial()
      : status = CurrentLocationStatus.initial,
        location = null,
        error = null;

  bool get isLoading => status == CurrentLocationStatus.loading;
}
