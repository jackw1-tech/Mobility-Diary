import 'dart:convert';
import 'dart:io';

import 'package:diary/features/acquisition/sync/trip_ingestion_api.dart';
import 'package:diary/network/dto/trip_privacy_export_dto.dart';
import 'package:diary/other/contants/api_contants.dart';

abstract class TripPrivacyExportService {
  Future<TripPrivacyExportDto> fetchExport(int tripId);
}

class TripPrivacyExportHttpService implements TripPrivacyExportService {
  final AccessTokenProvider _tokenProvider;
  final HttpClient _client;

  TripPrivacyExportHttpService({
    required AccessTokenProvider tokenProvider,
    HttpClient? client,
  })  : _tokenProvider = tokenProvider,
        _client = client ?? HttpClient();

  @override
  Future<TripPrivacyExportDto> fetchExport(int tripId) async {
    final data = await _sendJson(
      'GET',
      '/mobility/trips/$tripId/privacy-export',
    );
    return TripPrivacyExportDto.fromJson(data);
  }

  Future<Map<String, dynamic>> _sendJson(String method, String path) async {
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) {
      throw const IngestionApiException('Sessione non disponibile');
    }

    final request = await _client.openUrl(method, _uri(path));
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.contentLength = 0;

    final response = await request.close().timeout(const Duration(seconds: 30));
    final responseBody = await response.transform(utf8.decoder).join();
    final decoded = _tryDecodeMap(responseBody);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded?['detail'];
      throw IngestionApiException(
        detail is String ? detail : 'Export privacy non disponibile',
        statusCode: response.statusCode,
      );
    }
    if (decoded != null) return decoded;
    throw const IngestionApiException('Risposta export privacy non valida');
  }

  Map<String, dynamic>? _tryDecodeMap(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on FormatException {
      return null;
    }
    return null;
  }

  Uri _uri(String path) {
    final base = ApiConstants.baseApiUrl.endsWith('/')
        ? ApiConstants.baseApiUrl
            .substring(0, ApiConstants.baseApiUrl.length - 1)
        : ApiConstants.baseApiUrl;
    return Uri.parse('$base$path');
  }
}
