import 'package:diary/repositories/location_repository.dart';
import 'package:diary/state_management/cubits/current_location_cubit/current_location_cubit_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart' as ll;

class CurrentLocationCubit extends Cubit<CurrentLocationCubitState> {
  final LocationRepository _repository;

  CurrentLocationCubit(this._repository)
      : super(const CurrentLocationCubitState.initial());

  Future<ll.LatLng?> resolve() async {
    emit(
      const CurrentLocationCubitState(status: CurrentLocationStatus.loading),
    );
    try {
      final location = await _repository.currentLocation();
      if (isClosed) return null;
      emit(
        CurrentLocationCubitState(
          status: CurrentLocationStatus.loaded,
          location: location,
        ),
      );
      return location;
    } catch (error) {
      if (isClosed) return null;
      emit(
        CurrentLocationCubitState(
          status: CurrentLocationStatus.error,
          error: 'Posizione non disponibile: $error',
        ),
      );
      return null;
    }
  }
}
