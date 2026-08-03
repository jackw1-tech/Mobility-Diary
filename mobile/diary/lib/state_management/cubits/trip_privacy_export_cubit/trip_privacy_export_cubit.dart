import 'package:diary/model/entities/privacy/trip_privacy_export.dart';
import 'package:diary/repositories/trip_privacy_export_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'trip_privacy_export_state.dart';

class TripPrivacyExportCubit extends Cubit<TripPrivacyExportState> {
  final TripPrivacyExportRepository _repository;

  TripPrivacyExportCubit(this._repository)
      : super(const TripPrivacyExportState.initial());

  Future<void> load(int tripId) async {
    emit(state.copyWith(
      status: TripPrivacyExportStatus.loading,
      clearError: true,
    ));
    final result = await _repository.fetchExport(tripId);
    final failure = result.failure;
    if (failure != null) {
      emit(state.copyWith(
        status: TripPrivacyExportStatus.error,
        error: failure.message,
      ));
      return;
    }
    emit(state.copyWith(
      status: TripPrivacyExportStatus.ready,
      export: result.requireValue,
    ));
  }
}
