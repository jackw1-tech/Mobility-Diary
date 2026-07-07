import 'package:diary/features/trips/domain/trip_list_item.dart';

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
  final String? mutationError;

  const TripsListCubitState({
    required this.status,
    this.trips = const [],
    this.error,
    this.reloadingTripId,
    this.reloadError,
    this.mutatingTripId,
    this.mutationError,
  });

  const TripsListCubitState.initial()
      : status = TripsListStatus.initial,
        trips = const [],
        error = null,
        reloadingTripId = null,
        reloadError = null,
        mutatingTripId = null,
        mutationError = null;

  bool get isLoading => status == TripsListStatus.loading;
}
