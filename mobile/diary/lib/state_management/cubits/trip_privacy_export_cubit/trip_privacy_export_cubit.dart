import 'package:diary/network/dto/trip_privacy_export_dto.dart';
import 'package:diary/network/service/trip_privacy_export_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'trip_privacy_export_state.dart';

class TripPrivacyExportCubit extends Cubit<TripPrivacyExportState> {
  final TripPrivacyExportService _service;

  TripPrivacyExportCubit(this._service)
      : super(const TripPrivacyExportState.initial());

  Future<void> load(int tripId) async {
    emit(state.copyWith(
      status: TripPrivacyExportStatus.loading,
      clearError: true,
    ));
    try {
      final export = await _service.fetchExport(tripId);
      emit(state.copyWith(
        status: TripPrivacyExportStatus.ready,
        export: export,
      ));
    } catch (error) {
      emit(state.copyWith(
        status: TripPrivacyExportStatus.error,
        error: error.toString(),
      ));
    }
  }
}
