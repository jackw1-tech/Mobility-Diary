import 'dart:io';

import 'package:diary/network/dto/upload/active_upload_dto.dart';
import 'package:diary/network/dto/upload/upload_start_result_dto.dart';
import 'package:diary/network/dto/upload/upload_status_dto.dart';
import 'package:diary/network/dto/upload/inline_core_result_dto.dart';
import 'package:diary/network/dto/upload/presign_result_dto.dart';
import 'package:diary/network/dto/upload/replay_data_dto.dart';
import 'package:diary/network/service/trip_upload_service.dart';
import 'package:diary/other/constants/api_constants.dart';
import 'package:dio/dio.dart';

class TripUploadDioService implements TripUploadService {
  final AccessTokenProvider _tokenProvider;
  final Dio _dio;

  TripUploadDioService({
    required AccessTokenProvider tokenProvider,
    Dio? dio,
  })  : _tokenProvider = tokenProvider,
        _dio = dio ?? Dio() {
    _dio.options.baseUrl = ApiConstants.baseApiUrl;
  }

  static const String _base = '/upload/trips';

  Future<Options> _options() async {
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) {
      throw const UploadApiException('Sessione non disponibile');
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
  /// qualunque errore in [UploadApiException] via [_handleError]. Fattorizza
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
    if (error is UploadApiException) return error;
    if (error is DioException) {
      final response = error.response;
      if (response != null) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          final detail = data['detail'];
          return UploadApiException(
            detail is String ? detail : 'Richiesta upload fallita',
            statusCode: response.statusCode,
            body: data,
          );
        }
        return UploadApiException(
          'Richiesta upload fallita (HTTP ${response.statusCode})',
          statusCode: response.statusCode,
        );
      }
      return UploadApiException(error.message ?? 'Errore di rete');
    }
    return Exception(error.toString());
  }

  @override
  Future<ActiveUploadDto?> getActiveUpload() async {
    try {
      final response = await _dio.get(
        '$_base/active',
        options: await _options(),
      );
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return ActiveUploadDto.fromJson(data);
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
  Future<UploadStartResultDto> startUpload({
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
            if (sourceTripId != null)
              'source_trip_id': sourceTripId, // Nel caso replay
          },
          options: await _options(),
        ),
        (data) =>
            UploadStartResultDto.fromJson(data as Map<String, dynamic>),
      );

  @override
  Future<void> abandonUpload({
    required int uploadId,
    required String deviceId,
  }) =>
      _sendVoid(
        () async => _dio.post(
          '$_base/$uploadId/abandon',
          data: {'device_id': deviceId},
          options: await _options(),
        ),
      );

  @override
  Future<void> heartbeatUpload({
    required int uploadId,
    required String clientSessionId,
    required String deviceId,
  }) =>
      _sendVoid(
        () async => _dio.post(
          '$_base/$uploadId/heartbeat',
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
    int uploadId, {
    required int sequence,
    required String sha256,
  }) =>
      _send(
        () async => _dio.post(
          '$_base/$uploadId/parts/presign',
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
        throw UploadApiException(
          'Upload parte fallito',
          statusCode: e.response?.statusCode,
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> confirmPart(
    int uploadId, {
    required int sequence,
    required String sha256,
  }) =>
      _sendVoid(
        () async => _dio.post(
          '$_base/$uploadId/parts/confirm',
          data: {'sequence': sequence, 'sha256': sha256},
          options: await _options(),
        ),
      );

  @override
  Future<void> completeRawUpload(
    int uploadId, {
    required int totalParts,
  }) =>
      _sendVoid(
        () async => _dio.post(
          '$_base/$uploadId/complete-raw',
          data: {'total_parts': totalParts},
          options: await _options(),
        ),
      );

  @override
  Future<UploadStatusDto> getStatus(int uploadId) => _send(
        () async => _dio.get('$_base/$uploadId', options: await _options()),
        (data) => UploadStatusDto.fromJson(data as Map<String, dynamic>),
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
