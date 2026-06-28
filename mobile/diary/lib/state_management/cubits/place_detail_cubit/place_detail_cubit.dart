import 'package:diary/network/dto/place_review_dto.dart';
import 'package:diary/network/service/places_service.dart';
import 'package:diary/state_management/cubits/place_detail_cubit/place_detail_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Gestisce le azioni manuali su un singolo luogo (conferma, rifiuto, riattiva,
/// etichetta). Ogni azione restituisce il luogo aggiornato dal backend.
class PlaceDetailCubit extends Cubit<PlaceDetailState> {
  final PlacesService _service;

  PlaceDetailCubit(this._service, PlaceReviewDto place)
      : super(PlaceDetailState(place: place));

  Future<void> loadReviewStatus() async {
    try {
      final placeStatus = await _service.fetchPlacesStatus();
      emit(
        PlaceDetailState(
          place: state.place,
          canReview: placeStatus.isActionable,
        ),
      );
    } catch (_) {
      emit(
        PlaceDetailState(
          place: state.place,
          canReview: state.canReview,
          error: 'Impossibile verificare lo stato della review dei luoghi',
        ),
      );
    }
  }

  Future<void> confirm() => _run(() => _service.confirmPlace(state.place.id));

  Future<void> reject() => _run(() => _service.rejectPlace(state.place.id));

  Future<void> reactivate() =>
      _run(() => _service.reactivatePlace(state.place.id));

  Future<void> label(String category, String customName) => _run(
        () => _service.labelPlace(
          state.place.id,
          category: category,
          customName: customName,
        ),
      );

  Future<void> _run(Future<PlaceReviewDto> Function() action) async {
    if (!state.canReview) {
      emit(
        PlaceDetailState(
          place: state.place,
          canReview: false,
          error: 'Analisi dei luoghi abituali non completata',
        ),
      );
      return;
    }
    emit(PlaceDetailState(
        place: state.place, busy: true, canReview: state.canReview));
    try {
      emit(PlaceDetailState(place: await action(), canReview: true));
    } on PlaceMutationBlockedException catch (error) {
      emit(
        PlaceDetailState(
          place: state.place,
          canReview: false,
          error: error.message,
        ),
      );
    } catch (error) {
      emit(
        PlaceDetailState(
          place: state.place,
          canReview: state.canReview,
          error: error.toString(),
        ),
      );
    }
  }
}
