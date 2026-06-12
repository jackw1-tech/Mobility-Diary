class ApiConstants {
  static String get baseApiUrl {
    if (const bool.hasEnvironment('API_BASE_URL')) {
      return const String.fromEnvironment('API_BASE_URL');
    }
    return 'https://django-api-production-df02.up.railway.app/api';
  }

  static const String loginPath = '/auth/login';
  static const String registerPath = '/auth/register';
  static const String mePath = '/auth/me';
  static const String logoutPath = '/auth/logout';

  static const String mobilityTripsPath = '/trips/';
}

class Apicontants {
  @Deprecated('Use ApiConstants.baseApiUrl')
  static String get baseApiUrl => ApiConstants.baseApiUrl;
}
