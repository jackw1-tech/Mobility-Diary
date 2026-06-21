import 'package:diary/network/service/trips_service.dart';
import 'package:diary/state_management/cubits/trips_list_cubit/trips_list_cubit_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class TripsListCubit extends Cubit<TripsListCubitState> {
  final TripsService _service;

  TripsListCubit(this._service) : super(const TripsListCubitState.initial());

  Future<void> load() async {
    emit(const TripsListCubitState(status: TripsListStatus.loading));
    try {
      final trips = await _service.fetchTrips();
      emit(
        TripsListCubitState(
          status:
              trips.isEmpty ? TripsListStatus.empty : TripsListStatus.loaded,
          trips: trips,
        ),
      );
    } catch (error) {
      emit(
        TripsListCubitState(
          status: TripsListStatus.error,
          error: error.toString(),
        ),
      );
    }
  }
}
