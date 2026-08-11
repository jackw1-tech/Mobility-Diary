import 'dart:io';

import 'package:diary/network/service/trip_ingestion_service.dart';
import 'package:diary/network/dto/place_mining_status_dto.dart';
import 'package:diary/network/dto/place_review_dto.dart';
import 'package:diary/network/service/impl/http_json_utils.dart';

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
    final response =
        await sendAuthenticatedJson(_client, _tokenProvider, method, path,
            body: body);
    if (response.isError) {
      final blocked = _extractBlocked(response.statusCode, response.body);
      if (blocked != null) throw blocked;
      final detail = _extractDetail(response.body);
      throw IngestionApiException(
        detail ?? 'Richiesta luoghi fallita (HTTP ${response.statusCode})',
        statusCode: response.statusCode,
      );
    }
    return tryDecodeJson(response.body);
  }

  String? _extractDetail(String body) {
    final decoded = tryDecodeJson(body);
    if (decoded is Map && decoded['detail'] is String) {
      return decoded['detail'] as String;
    }
    return null;
  }

  PlaceMutationBlockedException? _extractBlocked(int statusCode, String body) {
    final decoded = tryDecodeJson(body);
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
}
