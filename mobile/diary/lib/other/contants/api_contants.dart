import 'package:flutter/foundation.dart';

class ApiConstants {
  static const String _localComposeApiUrl = 'http://localhost:8080/api';
  static const String _androidEmulatorComposeApiUrl =
      'http://10.0.2.2:8080/api';
  static const String _productionApiUrl =
      'https://mobilitydiary.giacomobianco.com/api';

  static String get baseApiUrl {
    return _productionApiUrl;
    if (const bool.hasEnvironment('API_BASE_URL')) {
      return const String.fromEnvironment('API_BASE_URL');
    }
    if (kDebugMode) {
      return defaultTargetPlatform == TargetPlatform.android
          ? _androidEmulatorComposeApiUrl
          : _localComposeApiUrl;
    }
    return _productionApiUrl;
  }

  static const String loginPath = '/auth/login';
  static const String registerPath = '/auth/register';
  static const String mePath = '/auth/me';
  static const String logoutPath = '/auth/logout';
  static const String privacySettingsPath = '/privacy/settings';

  static const String mobilityTripsPath = '/trips/';
}

class Apicontants {
  @Deprecated('Use ApiConstants.baseApiUrl')
  static String get baseApiUrl => ApiConstants.baseApiUrl;
}
