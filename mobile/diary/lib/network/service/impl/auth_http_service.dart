import 'dart:convert';
import 'dart:io';

import 'package:diary/network/dto/auth_session_dto.dart';
import 'package:diary/network/dto/user_dto.dart';
import 'package:diary/network/service/auth_service.dart';
import 'package:diary/other/constants/api_constants.dart';

class AuthHttpService implements AuthService {
  final HttpClient _client;

  AuthHttpService({HttpClient? client}) : _client = client ?? HttpClient();

  @override
  Future<AuthSessionDto> login({
    required String email,
    required String password,
    required String deviceName,
  }) async {
    final data = await _sendJson(
      method: 'POST',
      path: ApiConstants.loginPath,
      body: {
        'email': email,
        'password': password,
        'device_name': deviceName,
      },
      requiresAuth: false,
    );
    return AuthSessionDto.fromJson(data);
  }

  @override
  Future<AuthSessionDto> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String deviceName,
  }) async {
    final data = await _sendJson(
      method: 'POST',
      path: ApiConstants.registerPath,
      body: {
        'email': email,
        'password': password,
        'first_name': firstName,
        'last_name': lastName,
        'device_name': deviceName,
      },
      requiresAuth: false,
    );
    return AuthSessionDto.fromJson(data);
  }

  @override
  Future<UserDto> fetchCurrentUser({required String accessToken}) async {
    final data = await _sendJson(
      method: 'GET',
      path: ApiConstants.mePath,
      requiresAuth: true,
      accessToken: accessToken,
    );
    return UserDto.fromJson(data);
  }

  @override
  Future<void> logout({required String accessToken}) async {
    await _sendJson(
      method: 'POST',
      path: ApiConstants.logoutPath,
      requiresAuth: true,
      accessToken: accessToken,
    );
  }

  Future<Map<String, dynamic>> _sendJson({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    required bool requiresAuth,
    String? accessToken,
  }) async {
    final request = await _client
        .openUrl(method, _uri(path))
        .timeout(const Duration(seconds: 10));

    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (requiresAuth) {
      if (accessToken == null || accessToken.isEmpty) {
        throw const AuthApiException('Sessione non disponibile');
      }
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
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
}
