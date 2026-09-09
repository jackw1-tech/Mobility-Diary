import 'package:diary/repositories/places_repository.dart';
import 'package:diary/state_management/cubits/places_cubit/places_cubit_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class PlacesCubit extends Cubit<PlacesCubitState> {
  final PlacesRepository _repository;

  PlacesCubit(this._repository) : super(const PlacesCubitState.initial());

  Future<void> load() async {
    emit(const PlacesCubitState(status: PlacesStatus.loading));
    final statusResult = await _repository.fetchPlacesStatus();
    final statusFailure = statusResult.failure;
    if (statusFailure != null) {
      emit(
        PlacesCubitState(
          status: PlacesStatus.error,
          error: statusFailure.message,
        ),
      );
      return;
    }
    final placeStatus = statusResult.requireValue;
    if (placeStatus.isInProgress) {
      emit(
        PlacesCubitState(
          status: PlacesStatus.miningInProgress,
          placeStatus: placeStatus,
        ),
      );
      return;
    }
    final placesResult = await _repository.fetchPlaces();
    final placesFailure = placesResult.failure;
    if (placesFailure != null) {
      emit(
        PlacesCubitState(
          status: PlacesStatus.error,
          error: placesFailure.message,
        ),
      );
      return;
    }
    final places = placesResult.requireValue;
    emit(
      PlacesCubitState(
        status: places.isEmpty && placeStatus.isActionable
            ? PlacesStatus.empty
            : PlacesStatus.loaded,
        places: places,
        placeStatus: placeStatus,
      ),
    );
  }
}
