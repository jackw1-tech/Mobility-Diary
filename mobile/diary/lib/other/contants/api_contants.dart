class ApiConstants {
  static const String baseApiUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000/api',
  );

  static const String loginPath = '/auth/login';
  static const String registerPath = '/auth/register';
  static const String mePath = '/auth/me';
  static const String logoutPath = '/auth/logout';
}

class Apicontants {
  @Deprecated('Use ApiConstants.baseApiUrl')
  static const String baseApiUrl = ApiConstants.baseApiUrl;
}
