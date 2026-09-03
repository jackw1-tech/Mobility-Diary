import 'dart:io';

import 'package:diary/network/dto/ingestion/active_ingestion_dto.dart';
import 'package:diary/network/dto/ingestion/ingestion_start_result_dto.dart';
import 'package:diary/network/dto/ingestion/ingestion_status_dto.dart';
import 'package:diary/network/dto/ingestion/inline_core_result_dto.dart';
import 'package:diary/network/dto/ingestion/presign_result_dto.dart';
import 'package:diary/network/dto/ingestion/replay_data_dto.dart';
import 'package:diary/network/service/trip_ingestion_service.dart';
import 'package:diary/other/constants/api_constants.dart';
import 'package:dio/dio.dart';

class TripIngestionDioService implements TripIngestionService {
  final AccessTokenProvider _tokenProvider;
  final Dio _dio;

  TripIngestionDioService({
    required AccessTokenProvider tokenProvider,
    Dio? dio,
  })  : _tokenProvider = tokenProvider,
        _dio = dio ?? Dio() {
    _dio.options.baseUrl = ApiConstants.baseApiUrl;
  }

  static const String _base = '/ingestion/trips';

  Future<Options> _options() async {
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) {
      throw const IngestionApiException('Sessione non disponibile');
    }
    return Options(
      headers: {
        HttpHeaders.acceptHeader: 'application/json',
        HttpHeaders.authorizationHeader: 'Bearer $token',
      },
      contentType: Headers.jsonContentType,
    );
  }

  /// Esegue una richiesta Dio e mappa il body con [onSuccess], convertendo
  /// qualunque errore in [IngestionApiException] via [_handleError]. Fattorizza
  /// il try/catch identico ripetuto da quasi tutte le chiamate di questo
  /// service.
  Future<T> _send<T>(
    Future<Response<dynamic>> Function() request,
    T Function(dynamic data) onSuccess,
  ) async {
    try {
      final response = await request();
      return onSuccess(response.data);
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> _sendVoid(Future<Response<dynamic>> Function() request) =>
      _send(request, (_) {});

  Exception _handleError(Object error) {
    if (error is IngestionApiException) return error;
    if (error is DioException) {
      final response = error.response;
      if (response != null) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          final detail = data['detail'];
          return IngestionApiException(
            detail is String ? detail : 'Richiesta ingestion fallita',
            statusCode: response.statusCode,
            body: data,
          );
        }
        return IngestionApiException(
          'Richiesta ingestion fallita (HTTP ${response.statusCode})',
          statusCode: response.statusCode,
        );
      }
      return IngestionApiException(error.message ?? 'Errore di rete');
    }
    return Exception(error.toString());
  }

  @override
  Future<ActiveIngestionDto?> getActiveIngestion() async {
    try {
      final response = await _dio.get(
        '$_base/active',
        options: await _options(),
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return ActiveIngestionDto.fromJson(data);
      }
      return null;
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 404) {
        return null;
      }
      throw _handleError(e);
    }
  }

  @override
  Future<IngestionStartResultDto> startIngestion({
    required String clientSessionId,
    required DateTime startedAt,
    required String deviceId,
    String devicePlatform = '',
    int? sourceTripId,
  }) =>
      _send(
        () async => _dio.post(
          '$_base/start',
          data: {
            'client_session_id': clientSessionId,
            'schema_version': 1,
            'started_at': startedAt.toUtc().toIso8601String(),
            'device_id': deviceId,
            'device_platform': devicePlatform,
            if (sourceTripId != null) 'source_trip_id': sourceTripId,
          },
          options: await _options(),
        ),
        (data) =>
            IngestionStartResultDto.fromJson(data as Map<String, dynamic>),
      );

  @override
  Future<void> abandonIngestion({
    required int ingestionId,
    required String deviceId,
  }) =>
      _sendVoid(
        () async => _dio.post(
          '$_base/$ingestionId/abandon',
          data: {'device_id': deviceId},
          options: await _options(),
        ),
      );

  @override
  Future<void> heartbeatIngestion({
    required int ingestionId,
    required String clientSessionId,
    required String deviceId,
  }) =>
      _sendVoid(
        () async => _dio.post(
          '$_base/$ingestionId/heartbeat',
          data: {
            'client_session_id': clientSessionId,
            'device_id': deviceId,
          },
          options: await _options(),
        ),
      );

  // Mando i dati Gps e Transizioni al backend
  @override
  Future<InlineCoreResultDto> postCoreInline({
    required Map<String, dynamic> body,
  }) =>
      _send(
        () async =>
            _dio.post('$_base/core', data: body, options: await _options()),
        (data) => InlineCoreResultDto.fromJson(data as Map<String, dynamic>),
      );

  @override
  Future<PresignResultDto> presignPart(
    int ingestionId, {
    required int sequence,
    required String sha256,
  }) =>
      _send(
        () async => _dio.post(
          '$_base/$ingestionId/parts/presign',
          data: {
            'sequence': sequence,
            'sha256': sha256,
          },
          options: await _options(),
        ),
        (data) => PresignResultDto.fromJson(data as Map<String, dynamic>),
      );

  @override
  Future<void> uploadPart(
    String uploadUrl,
    List<int> bytes, {
    Map<String, String> headers = const {},
  }) async {
    try {
      final uploadHeaders = {
        ...headers,
        HttpHeaders.contentLengthHeader: bytes.length.toString(),
      };
      final options = Options(
        headers: uploadHeaders,
        contentType: uploadHeaders['content-type'] ??
            uploadHeaders['Content-Type'] ??
            'application/gzip',
        sendTimeout: const Duration(minutes: 5),
        receiveTimeout: const Duration(minutes: 5),
      );
      await _dio.put(
        uploadUrl,
        data: Stream.fromIterable([bytes]),
        options: options,
      );
    } catch (e) {
      if (e is DioException) {
        throw IngestionApiException(
          'Upload parte fallito',
          statusCode: e.response?.statusCode,
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> confirmPart(
    int ingestionId, {
    required int sequence,
    required String sha256,
  }) =>
      _sendVoid(
        () async => _dio.post(
          '$_base/$ingestionId/parts/confirm',
          data: {'sequence': sequence, 'sha256': sha256},
          options: await _options(),
        ),
      );

  @override
  Future<void> completeRawIngestion(
    int ingestionId, {
    required int totalParts,
  }) =>
      _sendVoid(
        () async => _dio.post(
          '$_base/$ingestionId/complete-raw',
          data: {'total_parts': totalParts},
          options: await _options(),
        ),
      );

  @override
  Future<IngestionStatusDto> getStatus(int ingestionId) => _send(
        () async => _dio.get('$_base/$ingestionId', options: await _options()),
        (data) => IngestionStatusDto.fromJson(data as Map<String, dynamic>),
      );

  @override
  Future<ReplayDataDto> getReplayData(int tripId) async {
    try {
      final response = await _dio.get(
        '/mobility/trips/reloadable/$tripId/replay-data',
        options: await _options(),
      );
      return ReplayDataDto.fromJson(
        Map<String, dynamic>.from(response.data as Map<dynamic, dynamic>),
      );
    } catch (e) {
      throw _handleError(e);
    }
  }

  @override
  Future<List<List<double>>> getReplaySensorWindow(
    int tripId,
    int offsetSeconds,
  ) async {
    try {
      final response = await _dio.get(
        '/mobility/trips/reloadable/$tripId/sensor-window?offset_seconds=$offsetSeconds',
        options: await _options(),
      );
      final data = response.data;
      final samples = data['samples'];
      if (samples is! List) return const [];
      return [
        for (final row in samples)
          if (row is List) [for (final value in row) (value as num).toDouble()],
      ];
    } catch (e) {
      throw _handleError(e);
    }
  }
}
