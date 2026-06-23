import 'package:diary/features/privacy/domain/privacy_level.dart';
import 'package:diary/network/service/privacy_settings_service.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'privacy_settings_state.dart';

class PrivacySettingsCubit extends Cubit<PrivacySettingsState> {
  final PrivacySettingsService _service;

  PrivacySettingsCubit(this._service)
      : super(const PrivacySettingsState.initial());

  Future<void> load() async {
    emit(
      state.copyWith(
        status: PrivacySettingsStatus.loading,
        clearError: true,
      ),
    );
    try {
      final level = await _service.fetch();
      emit(state.copyWith(status: PrivacySettingsStatus.ready, level: level));
    } catch (error) {
      emit(state.copyWith(
        status: PrivacySettingsStatus.error,
        error: error.toString(),
      ));
    }
  }

  Future<void> save(PrivacyLevel level) async {
    if (level == state.level && state.status == PrivacySettingsStatus.ready) {
      return;
    }

    final previousLevel = state.level;
    emit(state.copyWith(
      status: PrivacySettingsStatus.saving,
      level: level,
      clearError: true,
    ));
    try {
      final saved = await _service.update(level);
      emit(state.copyWith(status: PrivacySettingsStatus.ready, level: saved));
    } catch (error) {
      emit(state.copyWith(
        status: PrivacySettingsStatus.error,
        level: previousLevel,
        error: error.toString(),
      ));
    }
  }
}
