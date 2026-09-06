import 'package:diary/model/entities/trips/trip_list_item.dart';

enum TripsListStatus {
  initial,
  loading,
  loaded,
  empty,
  error,
}

class TripsListCubitState {
  final TripsListStatus status;
  final List<TripListItem> trips;
  final String? error;
  final int? reloadingTripId;
  final String? reloadError;
  final int? mutatingTripId;

  const TripsListCubitState({
    required this.status,
    this.trips = const [],
    this.error,
    this.reloadingTripId,
    this.reloadError,
    this.mutatingTripId,
  });

  const TripsListCubitState.initial()
      : status = TripsListStatus.initial,
        trips = const [],
        error = null,
        reloadingTripId = null,
        reloadError = null,
        mutatingTripId = null;

  bool get isLoading => status == TripsListStatus.loading;
}
