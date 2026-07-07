import 'dart:convert';
import 'dart:io';

import 'package:diary/network/service/trip_ingestion_service.dart';
import 'package:diary/network/dto/analytics_dto.dart';
import 'package:diary/other/contants/api_contants.dart';

abstract class AnalyticsService {
  Future<AnalyticsDto> fetchAnalytics({String granularity = 'day'});
}

class AnalyticsHttpService implements AnalyticsService {
  final AccessTokenProvider _tokenProvider;
  final HttpClient _client;

  AnalyticsHttpService({
    required AccessTokenProvider tokenProvider,
    HttpClient? client,
  })  : _tokenProvider = tokenProvider,
        _client = client ?? HttpClient();

  @override
  Future<AnalyticsDto> fetchAnalytics({String granularity = 'day'}) async {
    // Offset locale del dispositivo in minuti: bucketing sui giorni locali.
    final tz = DateTime.now().timeZoneOffset.inMinutes;
    final data = await _getJson(
      '/mobility/analytics?granularity=$granularity&tz=$tz',
    );
    return AnalyticsDto.fromJson(data);
  }

  Future<Map<String, dynamic>> _getJson(String path) async {
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) {
      throw const IngestionApiException('Sessione non disponibile');
    }

    final request = await _client.openUrl('GET', _uri(path));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.contentLength = 0;

    final response = await request.close().timeout(const Duration(seconds: 30));
    final body = await response.transform(utf8.decoder).join();
    final decoded = _tryDecodeMap(body);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded?['detail'];
      throw IngestionApiException(
        detail is String ? detail : 'Statistiche non disponibili',
        statusCode: response.statusCode,
      );
    }
    if (decoded != null) return decoded;
    throw const IngestionApiException('Risposta statistiche non valida');
  }

  Map<String, dynamic>? _tryDecodeMap(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
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
