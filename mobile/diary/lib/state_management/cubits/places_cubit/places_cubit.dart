import 'package:diary/network/service/places_service.dart';
import 'package:diary/state_management/cubits/places_cubit/places_cubit_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class PlacesCubit extends Cubit<PlacesCubitState> {
  final PlacesService _service;

  PlacesCubit(this._service) : super(const PlacesCubitState.initial());

  Future<void> load() async {
    emit(const PlacesCubitState(status: PlacesStatus.loading));
    try {
      final places = await _service.fetchPlaces();
      emit(
        PlacesCubitState(
          status:
              places.isEmpty ? PlacesStatus.empty : PlacesStatus.loaded,
          places: places,
        ),
      );
    } catch (error) {
      emit(
        PlacesCubitState(
          status: PlacesStatus.error,
          error: error.toString(),
        ),
      );
    }
  }
}
