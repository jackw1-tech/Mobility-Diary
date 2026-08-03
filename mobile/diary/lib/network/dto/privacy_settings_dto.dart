/// DTO grezzo (shape wire) delle impostazioni privacy utente
/// (`GET/PUT /privacy/settings`). Consumato solo da [PrivacySettingsMapper].
class PrivacySettingsDto {
  final String privacyLevel;
  final bool isFirstLogin;

  const PrivacySettingsDto({
    required this.privacyLevel,
    required this.isFirstLogin,
  });

  factory PrivacySettingsDto.fromJson(Map<String, dynamic> json) {
    return PrivacySettingsDto(
      privacyLevel: json['privacy_level'] as String? ?? '',
      isFirstLogin: json['is_first_login'] as bool? ?? false,
    );
  }
}
