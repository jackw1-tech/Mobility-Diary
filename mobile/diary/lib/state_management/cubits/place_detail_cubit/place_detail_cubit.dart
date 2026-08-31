import 'package:diary/utils/app_result.dart';
import 'package:diary/model/entities/places/place_mining_status.dart';
import 'package:diary/model/entities/places/place_review.dart';
import 'package:diary/repositories/places_repository.dart';
import 'package:diary/state_management/cubits/place_detail_cubit/place_detail_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Gestisce le azioni manuali su un singolo luogo (conferma, rifiuto, riattiva,
/// etichetta). Ogni azione restituisce il luogo aggiornato dal backend.
class PlaceDetailCubit extends Cubit<PlaceDetailState> {
  final PlacesRepository _repository;

  PlaceDetailCubit(this._repository, PlaceReview place)
      : super(PlaceDetailState.initial(place));

  Future<void> loadReviewStatus() async {
    final result = await _repository.fetchPlacesStatus();
    final failure = result.failure;
    if (failure == null) {
      emit(
        state.copyWith(
          status: PlaceDetailStatus.loaded,
          canReview: result.requireValue.isActionable,
          clearError: true,
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        status: PlaceDetailStatus.error,
        error: 'Impossibile verificare lo stato della review dei luoghi',
      ),
    );
  }

  Future<void> confirm() =>
      _run(() => _repository.confirmPlace(state.place.id));

  Future<void> reject() => _run(() => _repository.rejectPlace(state.place.id));

  Future<void> reactivate() =>
      _run(() => _repository.reactivatePlace(state.place.id));

  Future<void> label(String category, String customName) => _run(
        () => _repository.labelPlace(
          state.place.id,
          category: category,
          customName: customName,
        ),
      );

  Future<void> _run(Future<AppResult<PlaceReview>> Function() action) async {
    if (!state.canReview) {
      emit(
        state.copyWith(
          status: PlaceDetailStatus.error,
          canReview: false,
          error: 'Analisi dei luoghi abituali non completata',
        ),
      );
      return;
    }
    emit(state.copyWith(status: PlaceDetailStatus.loading, clearError: true));
    final result = await action();
    final failure = result.failure;
    if (failure == null) {
      emit(
        state.copyWith(
          status: PlaceDetailStatus.loaded,
          place: result.requireValue,
          canReview: true,
          clearError: true,
        ),
      );
      return;
    }
    final blocked = failure.cause;
    emit(
      state.copyWith(
        status: PlaceDetailStatus.error,
        canReview: blocked is PlaceReviewBlockedException ? false : null,
        error: blocked is PlaceReviewBlockedException
            ? blocked.message
            : failure.message,
      ),
    );
  }
}
