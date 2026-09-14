import 'package:diary/model/entities/privacy/privacy_level.dart';
import 'package:diary/repositories/privacy_settings_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'privacy_settings_state.dart';

class PrivacySettingsCubit extends Cubit<PrivacySettingsState> {
  final PrivacySettingsRepository _repository;

  PrivacySettingsCubit(this._repository)
    : super(const PrivacySettingsState.initial());

  Future<void> load() async {
    emit(
      state.copyWith(status: PrivacySettingsStatus.loading, clearError: true),
    );
    final result = await _repository.fetch();
    final failure = result.failure;
    if (failure != null) {
      emit(
        state.copyWith(
          status: PrivacySettingsStatus.error,
          error: failure.message,
        ),
      );
      return;
    }
    final settings = result.requireValue;
    emit(
      state.copyWith(
        status: PrivacySettingsStatus.ready,
        level: settings.level,
        isFirstLogin: settings.isFirstLogin,
      ),
    );
  }

  Future<void> save(PrivacyLevel level) async {
    final isNoOp =
        !state.isFirstLogin &&
        level == state.level &&
        state.status == PrivacySettingsStatus.ready;
    if (isNoOp) return;

    final previousLevel = state.level;
    emit(
      state.copyWith(
        status: PrivacySettingsStatus.saving,
        level: level,
        clearError: true,
      ),
    );
    final result = await _repository.update(level);
    final failure = result.failure;
    if (failure != null) {
      emit(
        state.copyWith(
          status: PrivacySettingsStatus.error,
          level: previousLevel,
          error: failure.message,
        ),
      );
      return;
    }
    final saved = result.requireValue;
    emit(
      state.copyWith(
        status: PrivacySettingsStatus.ready,
        level: saved.level,
        isFirstLogin: saved.isFirstLogin,
      ),
    );
  }
}
