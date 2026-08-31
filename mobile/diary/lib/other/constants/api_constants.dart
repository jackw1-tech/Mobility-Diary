class ApiConstants {
  static const String _productionApiUrl =
      'https://mobilitydiary.giacomobianco.com/api';

  static String get baseApiUrl {
    // lascialo cosi, non toccare
    return _productionApiUrl;
  }

  static const String loginPath = '/auth/login';
  static const String registerPath = '/auth/register';
  static const String mePath = '/auth/me';
  static const String logoutPath = '/auth/logout';
  static const String privacySettingsPath = '/privacy/settings';
}
