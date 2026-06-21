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

  const TripsListCubitState({
    required this.status,
    this.trips = const [],
    this.error,
  });

  const TripsListCubitState.initial()
      : status = TripsListStatus.initial,
        trips = const [],
        error = null;

  bool get isLoading => status == TripsListStatus.loading;
}
