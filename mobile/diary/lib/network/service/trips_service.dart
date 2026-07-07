import 'dart:convert';
import 'dart:io';

import 'package:diary/network/service/trip_ingestion_service.dart';
import 'package:diary/network/dto/trip_list_item_dto.dart';
import 'package:diary/network/dto/trip_reload_dto.dart';
import 'package:diary/network/dto/trip_reload_slots_dto.dart';
import 'package:diary/other/contants/api_contants.dart';

abstract class TripsService {
  Future<List<TripListItemDto>> fetchTrips();

  Future<List<TripListItemDto>> fetchReloadableTrips();

  Future<TripReloadSlotsDto> fetchReloadSlots(int sourceTripId);

  Future<void> deleteTrip(int tripId);

  Future<TripListItemDto> setTripReloadable({
    required int tripId,
    required bool isReloadable,
  });

  Future<TripListItemDto> updateTripNote({
    required int tripId,
    required String note,
  });

  Future<TripReloadDto> reloadTrip({
    required int sourceTripId,
    required String reloadRequestId,
    DateTime? scheduledStartAt,
  });
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
    return _tripItemsFromJson(data);
  }

  @override
  Future<List<TripListItemDto>> fetchReloadableTrips() async {
    final data = await _sendJsonList('GET', '/mobility/trips/reloadable');
    return _tripItemsFromJson(data);
  }

  @override
  Future<TripReloadSlotsDto> fetchReloadSlots(int sourceTripId) async {
    final data = await _sendJsonMap(
      'GET',
      '/mobility/trips/reloadable/$sourceTripId/slots?limit=100',
    );
    return TripReloadSlotsDto.fromJson(data);
  }

  @override
  Future<void> deleteTrip(int tripId) async {
    await _sendJson('DELETE', '/mobility/trips/$tripId');
  }

  @override
  Future<TripListItemDto> setTripReloadable({
    required int tripId,
    required bool isReloadable,
  }) async {
    final data = await _sendJsonMap(
      'PATCH',
      '/mobility/trips/$tripId/reloadable',
      body: {'is_reloadable': isReloadable},
    );
    return TripListItemDto.fromJson(data);
  }

  @override
  Future<TripListItemDto> updateTripNote({
    required int tripId,
    required String note,
  }) async {
    final data = await _sendJsonMap(
      'PATCH',
      '/mobility/trips/$tripId/note',
      body: {'note': note},
    );
    return TripListItemDto.fromJson(data);
  }

  @override
  Future<TripReloadDto> reloadTrip({
    required int sourceTripId,
    required String reloadRequestId,
    DateTime? scheduledStartAt,
  }) async {
    final body = <String, dynamic>{'reload_request_id': reloadRequestId};
    if (scheduledStartAt != null) {
      body['scheduled_start_at'] = scheduledStartAt.toUtc().toIso8601String();
    }
    final data = await _sendJsonMap(
      'POST',
      '/mobility/trips/reloadable/$sourceTripId/reload',
      body: body,
    );
    return TripReloadDto.fromJson(data);
  }

  List<TripListItemDto> _tripItemsFromJson(List<dynamic> data) {
    return data
        .map((item) =>
            TripListItemDto.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
  }

  Future<List<dynamic>> _sendJsonList(String method, String path) async {
    final decoded = await _sendJson(method, path);
    if (decoded is List) return decoded;
    throw const IngestionApiException('Risposta lista viaggi non valida');
  }

  Future<Map<String, dynamic>> _sendJsonMap(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final decoded = await _sendJson(method, path, body: body);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw const IngestionApiException('Risposta ricaricamento non valida');
  }

  Future<dynamic> _sendJson(
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
      final encoded = utf8.encode(jsonEncode(body));
      request.contentLength = encoded.length;
      request.add(encoded);
    } else {
      request.contentLength = 0;
    }

    final response = await request.close().timeout(const Duration(seconds: 30));
    final responseBody = await response.transform(utf8.decoder).join();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = _extractDetail(responseBody);
      throw IngestionApiException(
        detail ?? 'Richiesta viaggi fallita (HTTP ${response.statusCode})',
        statusCode: response.statusCode,
      );
    }

    final decoded = _tryDecode(responseBody);
    return decoded;
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
