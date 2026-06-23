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
  final bool isFirstLogin;
  final String? error;

  const PrivacySettingsState({
    required this.status,
    required this.level,
    required this.isFirstLogin,
    this.error,
  });

  const PrivacySettingsState.initial()
      : status = PrivacySettingsStatus.initial,
        level = PrivacyLevel.precise,
        isFirstLogin = false,
        error = null;

  bool get isLoading => status == PrivacySettingsStatus.loading;

  bool get isSaving => status == PrivacySettingsStatus.saving;

  bool get canSelect => status == PrivacySettingsStatus.ready;

  bool get needsPrivacyOnboarding =>
      status == PrivacySettingsStatus.ready && isFirstLogin;

  PrivacySettingsState copyWith({
    PrivacySettingsStatus? status,
    PrivacyLevel? level,
    bool? isFirstLogin,
    String? error,
    bool clearError = false,
  }) {
    return PrivacySettingsState(
      status: status ?? this.status,
      level: level ?? this.level,
      isFirstLogin: isFirstLogin ?? this.isFirstLogin,
      error: clearError ? null : error ?? this.error,
    );
  }
}
