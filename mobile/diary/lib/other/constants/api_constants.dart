class ApiConstants {
  static const String _productionApiUrl =
      'https://mobilitydiary.giacomobianco.com/api';

  static const String _apiBaseUrlOverride = String.fromEnvironment(
    'API_BASE_URL',
  );

  static String get baseApiUrl {
    if (_apiBaseUrlOverride.isNotEmpty) return _apiBaseUrlOverride;
    return _productionApiUrl;
  }

  static const String loginPath = '/auth/login';
  static const String registerPath = '/auth/register';
  static const String mePath = '/auth/me';
  static const String logoutPath = '/auth/logout';
  static const String privacySettingsPath = '/privacy/settings';
}
