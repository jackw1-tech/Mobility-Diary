import 'dart:io';

import 'package:diary/network/service/trip_upload_service.dart';
import 'package:diary/network/dto/analytics_dto.dart';
import 'package:diary/network/service/impl/http_json_utils.dart';

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
    final response =
        await sendAuthenticatedJson(_client, _tokenProvider, 'GET', path);
    final decoded = tryDecodeJsonMap(response.body);

    if (response.isError) {
      final detail = decoded?['detail'];
      throw UploadApiException(
        detail is String ? detail : 'Statistiche non disponibili',
        statusCode: response.statusCode,
      );
    }
    if (decoded != null) return decoded;
    throw const UploadApiException('Risposta statistiche non valida');
  }
}
