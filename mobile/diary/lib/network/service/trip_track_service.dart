import 'dart:convert';
import 'dart:io';

import 'package:diary/features/acquisition/sync/trip_ingestion_api.dart';
import 'package:diary/network/dto/trip_track_dto.dart';
import 'package:diary/other/contants/api_contants.dart';

abstract class TripTrackService {
  Future<TripTrackDto> fetchTrack(int tripId);
  Future<TripDiaryDto> fetchDiary(int tripId);
}

class TripTrackHttpService implements TripTrackService {
  final AccessTokenProvider _tokenProvider;
  final HttpClient _client;

  TripTrackHttpService({
    required AccessTokenProvider tokenProvider,
    HttpClient? client,
  })  : _tokenProvider = tokenProvider,
        _client = client ?? HttpClient();

  @override
  Future<TripTrackDto> fetchTrack(int tripId) async {
    final data = await _sendJson(
      'GET',
      '/mobility/trips/$tripId/track',
    );
    return TripTrackDto.fromJson(data);
  }

  @override
  Future<TripDiaryDto> fetchDiary(int tripId) async {
    final data = await _sendJson(
      'GET',
      '/mobility/trips/$tripId/diary',
    );
    return TripDiaryDto.fromJson(data);
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
    final decoded = _tryDecode(responseBody);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map ? decoded['detail'] : null;
      throw IngestionApiException(
        detail is String ? detail : 'Richiesta traiettoria fallita',
        statusCode: response.statusCode,
      );
    }
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw const IngestionApiException('Risposta traiettoria non valida');
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

  Uri _uri(String path) {
    final base = ApiConstants.baseApiUrl.endsWith('/')
        ? ApiConstants.baseApiUrl
            .substring(0, ApiConstants.baseApiUrl.length - 1)
        : ApiConstants.baseApiUrl;
    return Uri.parse('$base$path');
  }
}
