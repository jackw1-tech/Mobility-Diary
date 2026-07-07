import 'dart:io';

import 'package:diary/network/dto/ingestion/active_ingestion_dto.dart';
import 'package:diary/network/dto/ingestion/ingestion_start_result_dto.dart';
import 'package:diary/network/dto/ingestion/ingestion_status_dto.dart';
import 'package:diary/network/dto/ingestion/inline_core_result_dto.dart';
import 'package:diary/network/dto/ingestion/presign_result_dto.dart';
import 'package:diary/network/service/trip_ingestion_service.dart';
import 'package:diary/other/contants/api_contants.dart';
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
  }) async {
    try {
      final response = await _dio.post(
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
      );
      return IngestionStartResultDto.fromJson(response.data);
    } catch (e) {
      throw _handleError(e);
    }
  }

  @override
  Future<void> abandonIngestion({
    required int ingestionId,
    required String deviceId,
  }) async {
    try {
      await _dio.post(
        '$_base/$ingestionId/abandon',
        data: {'device_id': deviceId},
        options: await _options(),
      );
    } catch (e) {
      throw _handleError(e);
    }
  }

  @override
  Future<void> heartbeatIngestion({
    required int ingestionId,
    required String clientSessionId,
    required String deviceId,
  }) async {
    try {
      await _dio.post(
        '$_base/$ingestionId/heartbeat',
        data: {
          'client_session_id': clientSessionId,
          'device_id': deviceId,
        },
        options: await _options(),
      );
    } catch (e) {
      throw _handleError(e);
    }
  }

  @override
  Future<InlineCoreResultDto> postCoreInline({
    required Map<String, dynamic> body,
  }) async {
    try {
      final response = await _dio.post(
        '$_base/core',
        data: body,
        options: await _options(),
      );
      return InlineCoreResultDto.fromJson(response.data);
    } catch (e) {
      throw _handleError(e);
    }
  }

  @override
  Future<int> createIngestion({
    required String clientSessionId,
    required Map<String, int> expectedCoreParts,
    required Map<String, int> expectedRawParts,
    DateTime? startedAt,
    DateTime? endedAt,
    String deviceId = '',
    String devicePlatform = '',
  }) async {
    try {
      final response = await _dio.post(
        _base,
        data: {
          'client_session_id': clientSessionId,
          'schema_version': 1,
          'started_at': startedAt?.toUtc().toIso8601String(),
          'ended_at': endedAt?.toUtc().toIso8601String(),
          'device_id': deviceId,
          'device_platform': devicePlatform,
          'expected_core_parts': expectedCoreParts,
          'expected_raw_parts': expectedRawParts,
        },
        options: await _options(),
      );
      return response.data['ingestion_id'] as int;
    } catch (e) {
      throw _handleError(e);
    }
  }

  @override
  Future<PresignResultDto> presignPart(
    int ingestionId, {
    required String kind,
    required int sequence,
    required String sha256,
    required int sizeBytes,
  }) async {
    try {
      final response = await _dio.post(
        '$_base/$ingestionId/parts/presign',
        data: {
          'kind': kind,
          'sequence': sequence,
          'sha256': sha256,
          'size_bytes': sizeBytes,
        },
        options: await _options(),
      );
      return PresignResultDto.fromJson(response.data);
    } catch (e) {
      throw _handleError(e);
    }
  }

  @override
  Future<void> uploadPart(
    String uploadUrl,
    List<int> bytes, {
    Map<String, String> headers = const {},
  }) async {
    try {
      final options = Options(
        headers: headers,
        contentType: headers['content-type'] ??
            headers['Content-Type'] ??
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
    required String kind,
    required int sequence,
    required String sha256,
  }) async {
    try {
      await _dio.post(
        '$_base/$ingestionId/parts/confirm',
        data: {'kind': kind, 'sequence': sequence, 'sha256': sha256},
        options: await _options(),
      );
    } catch (e) {
      throw _handleError(e);
    }
  }

  @override
  Future<void> completeCoreIngestion(
    int ingestionId, {
    required int totalParts,
  }) async {
    try {
      await _dio.post(
        '$_base/$ingestionId/complete-core',
        data: {'total_parts': totalParts},
        options: await _options(),
      );
    } catch (e) {
      throw _handleError(e);
    }
  }

  @override
  Future<void> completeRawIngestion(
    int ingestionId, {
    required int totalParts,
  }) async {
    try {
      await _dio.post(
        '$_base/$ingestionId/complete-raw',
        data: {'total_parts': totalParts},
        options: await _options(),
      );
    } catch (e) {
      throw _handleError(e);
    }
  }

  @override
  Future<IngestionStatusDto> getStatus(int ingestionId) async {
    try {
      final response = await _dio.get(
        '$_base/$ingestionId',
        options: await _options(),
      );
      return IngestionStatusDto.fromJson(response.data);
    } catch (e) {
      throw _handleError(e);
    }
  }

  @override
  Future<Map<String, dynamic>> getReplayData(int tripId) async {
    try {
      final response = await _dio.get(
        '/mobility/trips/reloadable/$tripId/replay-data',
        options: await _options(),
      );
      return response.data;
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
