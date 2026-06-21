import 'dart:convert';
import 'dart:io';

import 'package:diary/features/acquisition/sync/trip_ingestion_api.dart';
import 'package:diary/network/dto/trip_list_item_dto.dart';
import 'package:diary/other/contants/api_contants.dart';

abstract class TripsService {
  Future<List<TripListItemDto>> fetchTrips();
}

class TripsHttpService implements TripsService {
  final AccessTokenProvider _tokenProvider;
  final HttpClient _client;

  TripsHttpService({
    required AccessTokenProvider tokenProvider,
    HttpClient? client,
  })  : _tokenProvider = tokenProvider,
        _client = client ?? HttpClient();

  @override
  Future<List<TripListItemDto>> fetchTrips() async {
    final data = await _sendJsonList('GET', '/mobility/trips');
    return data
        .map((item) =>
            TripListItemDto.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<List<dynamic>> _sendJsonList(String method, String path) async {
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

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = _extractDetail(responseBody);
      throw IngestionApiException(
        detail ?? 'Richiesta lista viaggi fallita (HTTP ${response.statusCode})',
        statusCode: response.statusCode,
      );
    }

    final decoded = _tryDecode(responseBody);
    if (decoded is List) return decoded;
    throw const IngestionApiException('Risposta lista viaggi non valida');
  }

  /// Decodifica JSON senza lanciare: un 405/500 puo' tornare testo o HTML.
  dynamic _tryDecode(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  String? _extractDetail(String body) {
    final decoded = _tryDecode(body);
    if (decoded is Map && decoded['detail'] is String) {
      return decoded['detail'] as String;
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
