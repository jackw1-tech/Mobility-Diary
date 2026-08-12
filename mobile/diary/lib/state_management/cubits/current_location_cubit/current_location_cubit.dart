import 'package:diary/repositories/location_repository.dart';
import 'package:diary/state_management/cubits/current_location_cubit/current_location_cubit_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart' as ll;

/// Espone la posizione corrente alla UI senza che questa debba parlare con il
/// [LocationRepository]: la mappa live la usa per il centro iniziale e per il
/// pulsante "ricentra".
class CurrentLocationCubit extends Cubit<CurrentLocationCubitState> {
  final LocationRepository _repository;

  CurrentLocationCubit(this._repository)
      : super(const CurrentLocationCubitState.initial());

  /// Risolve la posizione corrente e la pubblica nello stato. Ritorna anche il
  /// valore letto (`null` se non disponibile) per i chiamanti che devono
  /// reagire subito, ad esempio per animare la camera.
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
