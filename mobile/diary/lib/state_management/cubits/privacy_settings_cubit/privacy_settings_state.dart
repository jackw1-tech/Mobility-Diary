part of 'privacy_settings_cubit.dart';

enum PrivacySettingsStatus {
  initial,
  loading,
  ready,
  saving,
  error,
}

class PrivacySettingsState {
  final PrivacySettingsStatus status;
  final PrivacyLevel level;
  final String? error;

  const PrivacySettingsState({
    required this.status,
    required this.level,
    this.error,
  });

  const PrivacySettingsState.initial()
      : status = PrivacySettingsStatus.initial,
        level = PrivacyLevel.precise,
        error = null;

  bool get isLoading => status == PrivacySettingsStatus.loading;

  bool get isSaving => status == PrivacySettingsStatus.saving;

  bool get canSelect => status == PrivacySettingsStatus.ready;

  PrivacySettingsState copyWith({
    PrivacySettingsStatus? status,
    PrivacyLevel? level,
    String? error,
    bool clearError = false,
  }) {
    return PrivacySettingsState(
      status: status ?? this.status,
      level: level ?? this.level,
      error: clearError ? null : error ?? this.error,
    );
  }
}
