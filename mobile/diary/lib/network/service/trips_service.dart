import 'dart:io';

import 'package:diary/network/service/trip_upload_service.dart';
import 'package:diary/network/dto/trip_list_item_dto.dart';
import 'package:diary/network/dto/trip_reload_dto.dart';
import 'package:diary/network/dto/trip_reload_slots_dto.dart';
import 'package:diary/network/service/impl/http_json_utils.dart';
import 'package:diary/utils/trip_reload_diagnostics.dart';

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
      diagnosticsTripId: sourceTripId,
      requestName: 'slots',
    );
    final stopwatch = Stopwatch()..start();
    final dto = TripReloadSlotsDto.fromJson(data);
    TripReloadDiagnostics.eventForTrip(
      sourceTripId,
      'slots_dto_parsed',
      fields: {
        'duration_ms': stopwatch.elapsedMilliseconds,
        'slot_count': dto.slots.length,
      },
    );
    return dto;
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
      diagnosticsTripId: sourceTripId,
      requestName: 'reload',
    );
    final stopwatch = Stopwatch()..start();
    final dto = TripReloadDto.fromJson(data);
    TripReloadDiagnostics.eventForTrip(
      sourceTripId,
      'reload_dto_parsed',
      fields: {
        'duration_ms': stopwatch.elapsedMilliseconds,
        'derived_trip': dto.tripId,
        'gps_points': dto.gpsPoints,
        'path_points': dto.pathPoints,
      },
    );
    return dto;
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
    throw const UploadApiException('Risposta lista viaggi non valida');
  }

  Future<Map<String, dynamic>> _sendJsonMap(
    String method,
    String path, {
    Map<String, dynamic>? body,
    int? diagnosticsTripId,
    String? requestName,
  }) async {
    final decoded = await _sendJson(
      method,
      path,
      body: body,
      diagnosticsTripId: diagnosticsTripId,
      requestName: requestName,
    );
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw const UploadApiException('Risposta ricaricamento non valida');
  }

  /// [diagnosticsTripId] e [requestName] sono valorizzati solo dalle chiamate
  /// del caricamento diretto: senza traccia aperta sul viaggio sorgente gli
  /// eventi non producono alcuna riga di log.
  Future<dynamic> _sendJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    int? diagnosticsTripId,
    String? requestName,
  }) async {
    if (diagnosticsTripId != null && requestName != null) {
      TripReloadDiagnostics.eventForTrip(
        diagnosticsTripId,
        '${requestName}_http_start',
      );
    }
    final response = await sendAuthenticatedJson(
      _client,
      _tokenProvider,
      method,
      path,
      body: body,
      onDiagnostic: diagnosticsTripId == null || requestName == null
          ? null
          : (event) {
              TripReloadDiagnostics.eventForTrip(
                diagnosticsTripId,
                '${requestName}_http_${event.stage}',
                fields: {
                  'stage_ms': event.stageDuration.inMilliseconds,
                  'http_total_ms': event.totalDuration.inMilliseconds,
                  if (event.statusCode != null) 'status': event.statusCode,
                  if (event.declaredContentLength != null)
                    'content_length': event.declaredContentLength,
                  if (event.bodyCharacters != null)
                    'body_characters': event.bodyCharacters,
                  if (event.errorType != null) 'error_type': event.errorType,
                },
              );
            },
    );
    if (response.isError) {
      if (diagnosticsTripId != null && requestName != null) {
        TripReloadDiagnostics.eventForTrip(
          diagnosticsTripId,
          '${requestName}_http_error',
          fields: {'status': response.statusCode},
        );
      }
      final detail = _extractDetail(response.body);
      throw UploadApiException(
        detail ?? 'Richiesta viaggi fallita (HTTP ${response.statusCode})',
        statusCode: response.statusCode,
      );
    }
    final decodeWatch = Stopwatch()..start();
    final decoded = tryDecodeJson(response.body);
    if (diagnosticsTripId != null && requestName != null) {
      TripReloadDiagnostics.eventForTrip(
        diagnosticsTripId,
        '${requestName}_json_decode_complete',
        fields: {
          'duration_ms': decodeWatch.elapsedMilliseconds,
          'decoded_map': decoded is Map,
        },
      );
    }
    return decoded;
  }

  String? _extractDetail(String body) {
    final decoded = tryDecodeJson(body);
    if (decoded is Map && decoded['detail'] is String) {
      return decoded['detail'] as String;
    }
    return null;
  }
}
