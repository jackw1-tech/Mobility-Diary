import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:diary/features/auth/domain/auth_session.dart';
import 'package:diary/features/auth/domain/auth_user.dart';
import 'package:diary/other/contants/api_contants.dart';
import 'package:diary/repositories/auth_repository.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthApiException implements Exception {
  final String message;

  const AuthApiException(this.message);

  @override
  String toString() => message;
}

class AuthRepositoryImpl implements AuthRepository {
  static const _tokenKey = 'auth.access_token';
  static const _expiresAtKey = 'auth.expires_at';
  static const _userKey = 'auth.user';

  final FlutterSecureStorage _storage;
  final HttpClient _client;

  AuthUser? _currentUser;
  String? _accessToken;

  AuthRepositoryImpl({
    FlutterSecureStorage? storage,
    HttpClient? client,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _client = client ?? HttpClient();

  @override
  AuthUser? get currentUser => _currentUser;

  @override
  String? get accessToken => _accessToken;

  @override
  bool get isAuthenticated => _accessToken != null && _currentUser != null;

  @override
  Future<AuthSession?> restoreSession() async {
    final storedToken = await _storage.read(key: _tokenKey);
    if (storedToken == null || storedToken.isEmpty) {
      return null;
    }

    _accessToken = storedToken;
    try {
      final user = await loadCurrentUser();
      final expiresAtValue = await _storage.read(key: _expiresAtKey);
      final expiresAt = expiresAtValue == null
          ? DateTime.now().add(const Duration(days: 30))
          : DateTime.parse(expiresAtValue);

      return AuthSession(
        user: user,
        accessToken: storedToken,
        tokenType: 'Bearer',
        expiresAt: expiresAt,
      );
    } catch (_) {
      await _clearSession();
      return null;
    }
  }

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) {
    return _authenticate(
      ApiConstants.loginPath,
      {
        'email': email,
        'password': password,
        'device_name': _deviceName,
      },
    );
  }

  @override
  Future<AuthSession> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) {
    return _authenticate(
      ApiConstants.registerPath,
      {
        'email': email,
        'password': password,
        'first_name': firstName,
        'last_name': lastName,
        'device_name': _deviceName,
      },
    );
  }

  @override
  Future<AuthUser> loadCurrentUser() async {
    final data = await _sendJson(
      method: 'GET',
      path: ApiConstants.mePath,
      requiresAuth: true,
    );
    final user = AuthUser.fromJson(data);
    _currentUser = user;
    await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
    return user;
  }

  @override
  Future<void> logout() async {
    if (_accessToken != null) {
      try {
        await _sendJson(
          method: 'POST',
          path: ApiConstants.logoutPath,
          requiresAuth: true,
        );
      } catch (_) {
        // Local logout must still succeed if the server is unavailable.
      }
    }
    await _clearSession();
  }

  Future<AuthSession> _authenticate(
    String path,
    Map<String, dynamic> body,
  ) async {
    final data = await _sendJson(
      method: 'POST',
      path: path,
      body: body,
      requiresAuth: false,
    );
    final session = AuthSession.fromJson(data);
    await _persistSession(session);
    return session;
  }

  Future<void> _persistSession(AuthSession session) async {
    _accessToken = session.accessToken;
    _currentUser = session.user;
    await _storage.write(key: _tokenKey, value: session.accessToken);
    await _storage.write(
      key: _expiresAtKey,
      value: session.expiresAt.toIso8601String(),
    );
    await _storage.write(
        key: _userKey, value: jsonEncode(session.user.toJson()));
  }

  Future<void> _clearSession() async {
    _accessToken = null;
    _currentUser = null;
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _expiresAtKey);
    await _storage.delete(key: _userKey);
  }

  Future<Map<String, dynamic>> _sendJson({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    required bool requiresAuth,
  }) async {
    final request = await _client
        .openUrl(method, _uri(path))
        .timeout(const Duration(seconds: 10));

    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (requiresAuth) {
      final token = _accessToken;
      if (token == null || token.isEmpty) {
        throw const AuthApiException('Sessione non disponibile');
      }
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    }
    if (body != null) {
      final encodedBody = utf8.encode(jsonEncode(body));
      request.contentLength = encodedBody.length;
      request.add(encodedBody);
    } else {
      request.contentLength = 0;
    }

    final response = await request.close().timeout(const Duration(seconds: 20));
    final responseBody = await response.transform(utf8.decoder).join();
    final decoded = responseBody.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(responseBody) as Map<String, dynamic>;

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded['detail'];
      throw AuthApiException(
        detail is String ? detail : 'Richiesta non riuscita',
      );
    }

    return decoded;
  }

  Uri _uri(String path) {
    final base = ApiConstants.baseApiUrl.endsWith('/')
        ? ApiConstants.baseApiUrl
            .substring(0, ApiConstants.baseApiUrl.length - 1)
        : ApiConstants.baseApiUrl;
    return Uri.parse('$base$path');
  }

  String get _deviceName {
    if (Platform.isIOS) {
      return 'iOS';
    }
    if (Platform.isAndroid) {
      return 'Android';
    }
    return Platform.operatingSystem;
  }
}
