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
      final settings = await _service.fetch();
      emit(state.copyWith(
        status: PrivacySettingsStatus.ready,
        level: settings.level,
        isFirstLogin: settings.isFirstLogin,
      ));
    } catch (error) {
      emit(state.copyWith(
        status: PrivacySettingsStatus.error,
        error: error.toString(),
      ));
    }
  }

  Future<void> save(PrivacyLevel level) async {
    // While onboarding (isFirstLogin) we must save even the unchanged default,
    // otherwise the backend flag never clears and the dialog keeps reopening.
    final isNoOp = !state.isFirstLogin &&
        level == state.level &&
        state.status == PrivacySettingsStatus.ready;
    if (isNoOp) return;

    final previousLevel = state.level;
    emit(state.copyWith(
      status: PrivacySettingsStatus.saving,
      level: level,
      clearError: true,
    ));
    try {
      final saved = await _service.update(level);
      emit(state.copyWith(
        status: PrivacySettingsStatus.ready,
        level: saved.level,
        isFirstLogin: saved.isFirstLogin,
      ));
    } catch (error) {
      emit(state.copyWith(
        status: PrivacySettingsStatus.error,
        level: previousLevel,
        error: error.toString(),
      ));
    }
  }
}
