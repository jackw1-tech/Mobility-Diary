import 'dart:convert';
import 'dart:io';

import 'package:diary/features/acquisition/sync/trip_ingestion_api.dart';
import 'package:diary/features/privacy/domain/privacy_level.dart';
import 'package:diary/other/contants/api_contants.dart';

abstract class PrivacySettingsService {
  Future<PrivacyLevel> fetch();
  Future<PrivacyLevel> update(PrivacyLevel level);
}

class PrivacySettingsHttpService implements PrivacySettingsService {
  final AccessTokenProvider _tokenProvider;
  final HttpClient _client;

  PrivacySettingsHttpService({
    required AccessTokenProvider tokenProvider,
    HttpClient? client,
  })  : _tokenProvider = tokenProvider,
        _client = client ?? HttpClient();

  @override
  Future<PrivacyLevel> fetch() async {
    final data = await _sendJson('GET', ApiConstants.privacySettingsPath);
    return PrivacyLevel.fromWire(data['privacy_level'] as String? ?? '');
  }

  @override
  Future<PrivacyLevel> update(PrivacyLevel level) async {
    final data = await _sendJson(
      'PUT',
      ApiConstants.privacySettingsPath,
      body: {'privacy_level': level.wireName},
    );
    return PrivacyLevel.fromWire(data['privacy_level'] as String? ?? '');
  }

  Future<Map<String, dynamic>> _sendJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) {
      throw const IngestionApiException('Sessione non disponibile');
    }

    final request = await _client.openUrl(method, _uri(path));
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    if (body == null) {
      request.contentLength = 0;
    } else {
      final encodedBody = utf8.encode(jsonEncode(body));
      request.contentLength = encodedBody.length;
      request.add(encodedBody);
    }

    final response = await request.close().timeout(const Duration(seconds: 30));
    final responseBody = await response.transform(utf8.decoder).join();
    final decoded = _tryDecode(responseBody);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map ? decoded['detail'] : null;
      throw IngestionApiException(
        detail is String ? detail : 'Impostazioni privacy non disponibili',
        statusCode: response.statusCode,
      );
    }
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw const IngestionApiException('Risposta privacy non valida');
  }

  dynamic _tryDecode(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  Uri _uri(String path) {
    final base = ApiConstants.baseApiUrl.endsWith('/')
        ? ApiConstants.baseApiUrl
            .substring(0, ApiConstants.baseApiUrl.length - 1)
        : ApiConstants.baseApiUrl;
    return Uri.parse('$base$path');
  }
}
