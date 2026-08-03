import 'dart:convert';
import 'dart:io';

import 'package:diary/network/service/trip_ingestion_service.dart';
import 'package:diary/network/dto/place_mining_status_dto.dart';
import 'package:diary/network/dto/place_review_dto.dart';
import 'package:diary/other/constants/api_constants.dart';

abstract class PlacesService {
  Future<PlaceMiningStatusDto> fetchPlacesStatus();
  Future<List<PlaceReviewDto>> fetchPlaces();
  Future<PlaceReviewDto> confirmPlace(int id);
  Future<PlaceReviewDto> rejectPlace(int id);
  Future<PlaceReviewDto> reactivatePlace(int id);
  Future<PlaceReviewDto> labelPlace(
    int id, {
    required String category,
    required String customName,
  });
}

class PlaceMutationBlockedException extends IngestionApiException {
  final PlaceMiningStatusDto placeStatus;

  const PlaceMutationBlockedException(
    super.message, {
    required this.placeStatus,
    super.statusCode,
  });
}

class PlacesHttpService implements PlacesService {
  final AccessTokenProvider _tokenProvider;
  final HttpClient _client;

  PlacesHttpService({
    required AccessTokenProvider tokenProvider,
    HttpClient? client,
  })  : _tokenProvider = tokenProvider,
        _client = client ?? HttpClient();

  @override
  Future<PlaceMiningStatusDto> fetchPlacesStatus() async {
    final data = await _send('GET', '/mobility/places/status');
    if (data is! Map) {
      throw const IngestionApiException('Stato luoghi non valido');
    }
    return PlaceMiningStatusDto.fromJson(Map<String, dynamic>.from(data));
  }

  @override
  Future<List<PlaceReviewDto>> fetchPlaces() async {
    final data = await _send('GET', '/mobility/places');
    if (data is! List) {
      throw const IngestionApiException('Risposta luoghi non valida');
    }
    return data
        .map((item) =>
            PlaceReviewDto.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  @override
  Future<PlaceReviewDto> confirmPlace(int id) => _action('$id/confirm');

  @override
  Future<PlaceReviewDto> rejectPlace(int id) => _action('$id/reject');

  @override
  Future<PlaceReviewDto> reactivatePlace(int id) => _action('$id/reactivate');

  @override
  Future<PlaceReviewDto> labelPlace(
    int id, {
    required String category,
    required String customName,
  }) =>
      _action(
        '$id/label',
        body: {'category': category, 'custom_name': customName},
      );

  Future<PlaceReviewDto> _action(String suffix,
      {Map<String, dynamic>? body}) async {
    final data = await _send('POST', '/mobility/places/$suffix', body: body);
    if (data is! Map) {
      throw const IngestionApiException('Risposta azione luogo non valida');
    }
    return PlaceReviewDto.fromJson(Map<String, dynamic>.from(data));
  }

  Future<dynamic> _send(
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
    if (body != null) {
      final payload = utf8.encode(jsonEncode(body));
      request.contentLength = payload.length;
      request.add(payload);
    } else {
      request.contentLength = 0;
    }

    final response = await request.close().timeout(const Duration(seconds: 30));
    final responseBody = await response.transform(utf8.decoder).join();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final blocked = _extractBlocked(response.statusCode, responseBody);
      if (blocked != null) throw blocked;
      final detail = _extractDetail(responseBody);
      throw IngestionApiException(
        detail ?? 'Richiesta luoghi fallita (HTTP ${response.statusCode})',
        statusCode: response.statusCode,
      );
    }
    return _tryDecode(responseBody);
  }

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

  PlaceMutationBlockedException? _extractBlocked(int statusCode, String body) {
    final decoded = _tryDecode(body);
    if (statusCode != 409 || decoded is! Map) return null;
    if (decoded['code'] != 'place_mining_not_ready') return null;
    final status = decoded['status'] as String?;
    if (status == null || status.isEmpty) return null;
    return PlaceMutationBlockedException(
      (decoded['detail'] as String?) ??
          'Analisi dei luoghi abituali non completata',
      placeStatus: PlaceMiningStatusDto(status: status),
      statusCode: statusCode,
    );
  }

  Uri _uri(String path) {
    final base = ApiConstants.baseApiUrl.endsWith('/')
        ? ApiConstants.baseApiUrl
            .substring(0, ApiConstants.baseApiUrl.length - 1)
        : ApiConstants.baseApiUrl;
    return Uri.parse('$base$path');
  }
}
