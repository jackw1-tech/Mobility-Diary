import 'package:diary/network/dto/trip_list_item_dto.dart';

enum TripsListStatus {
  initial,
  loading,
  loaded,
  empty,
  error,
}

class TripsListCubitState {
  final TripsListStatus status;
  final List<TripListItemDto> trips;
  final String? error;
  final int? reloadingTripId;
  final String? reloadError;

  const TripsListCubitState({
    required this.status,
    this.trips = const [],
    this.error,
    this.reloadingTripId,
    this.reloadError,
  });

  const TripsListCubitState.initial()
      : status = TripsListStatus.initial,
        trips = const [],
        error = null,
        reloadingTripId = null,
        reloadError = null;

  bool get isLoading => status == TripsListStatus.loading;
}
