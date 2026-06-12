import 'dart:convert';
import 'dart:io';

import 'package:diary/other/contants/api_contants.dart';

/// Fornisce il bearer token corrente (da AuthRepository). Null se non loggato.
typedef AccessTokenProvider = Future<String?> Function();

class IngestionApiException implements Exception {
  final String message;
  final int? statusCode;
  const IngestionApiException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

class PresignResult {
  final String objectKey;
  final String uploadUrl;
  final Map<String, String> uploadHeaders;

  const PresignResult({
    required this.objectKey,
    required this.uploadUrl,
    this.uploadHeaders = const {},
  });
}

class IngestionStatus {
  final String status;
  final List<({String kind, int sequence})> missingParts;
  final int? tripId;

  const IngestionStatus({
    required this.status,
    required this.missingParts,
    this.tripId,
  });

  bool get isProcessed => status == 'PROCESSED' || status == 'COMPLETED';
  bool get isFailedFinal => status == 'FAILED_FINAL';
  bool get isBackendProcessing {
    return status == 'QUEUED' ||
        status == 'PROCESSING' ||
        status == 'FAILED_RETRYABLE';
  }

  bool get canReceiveParts {
    return status == 'CREATED' ||
        status == 'RECEIVING' ||
        status == 'READY_TO_PROCESS';
  }
}

/// Client REST dell'ingestione asincrona. Astratto per poter essere mockato
/// nei test della coda di sync.
abstract class TripIngestionApi {
  Future<int> createIngestion({
    required String clientSessionId,
    required Map<String, int> expectedParts,
    DateTime? startedAt,
    DateTime? endedAt,
    String deviceId,
    String devicePlatform,
  });

  Future<PresignResult> presignPart(
    int ingestionId, {
    required String kind,
    required int sequence,
    required String sha256,
    required int sizeBytes,
  });

  Future<void> uploadPart(
    String uploadUrl,
    List<int> bytes, {
    Map<String, String> headers,
  });

  Future<void> confirmPart(
    int ingestionId, {
    required String kind,
    required int sequence,
    required String sha256,
  });

  Future<void> completeIngestion(int ingestionId, {required int totalParts});

  Future<IngestionStatus> getStatus(int ingestionId);
}

/// Implementazione HTTP basata su dart:io, con bearer token.
class TripIngestionHttpApi implements TripIngestionApi {
  final AccessTokenProvider _tokenProvider;
  final HttpClient _client;

  TripIngestionHttpApi({
    required AccessTokenProvider tokenProvider,
    HttpClient? client,
  })  : _tokenProvider = tokenProvider,
        _client = client ?? HttpClient();

  static const String _base = '/ingestion/trips';

  @override
  Future<int> createIngestion({
    required String clientSessionId,
    required Map<String, int> expectedParts,
    DateTime? startedAt,
    DateTime? endedAt,
    String deviceId = '',
    String devicePlatform = '',
  }) async {
    final data = await _sendJson('POST', _base, body: {
      'client_session_id': clientSessionId,
      'schema_version': 1,
      'started_at': startedAt?.toUtc().toIso8601String(),
      'ended_at': endedAt?.toUtc().toIso8601String(),
      'device_id': deviceId,
      'device_platform': devicePlatform,
      'expected_parts': expectedParts,
    });
    return data['ingestion_id'] as int;
  }

  @override
  Future<PresignResult> presignPart(
    int ingestionId, {
    required String kind,
    required int sequence,
    required String sha256,
    required int sizeBytes,
  }) async {
    final data = await _sendJson(
      'POST',
      '$_base/$ingestionId/parts/presign',
      body: {
        'kind': kind,
        'sequence': sequence,
        'sha256': sha256,
        'size_bytes': sizeBytes,
      },
    );
    return PresignResult(
      objectKey: data['object_key'] as String,
      uploadUrl: data['upload_url'] as String,
      uploadHeaders: Map<String, String>.from(
        data['upload_headers'] as Map<dynamic, dynamic>? ?? const {},
      ),
    );
  }

  @override
  Future<void> uploadPart(
    String uploadUrl,
    List<int> bytes, {
    Map<String, String> headers = const {},
  }) async {
    final request = await _client.putUrl(Uri.parse(uploadUrl));
    request.headers.contentType = ContentType('application', 'gzip');
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'content-type') {
        request.headers.contentType = ContentType.parse(entry.value);
      } else {
        request.headers.set(entry.key, entry.value);
      }
    }
    request.contentLength = bytes.length;
    request.add(bytes);
    final response = await request.close().timeout(const Duration(minutes: 5));
    await response.drain<void>();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw IngestionApiException(
        'Upload parte fallito',
        statusCode: response.statusCode,
      );
    }
  }

  @override
  Future<void> confirmPart(
    int ingestionId, {
    required String kind,
    required int sequence,
    required String sha256,
  }) async {
    await _sendJson(
      'POST',
      '$_base/$ingestionId/parts/confirm',
      body: {'kind': kind, 'sequence': sequence, 'sha256': sha256},
    );
  }

  @override
  Future<void> completeIngestion(
    int ingestionId, {
    required int totalParts,
  }) async {
    await _sendJson(
      'POST',
      '$_base/$ingestionId/complete',
      body: {'total_parts': totalParts},
    );
  }

  @override
  Future<IngestionStatus> getStatus(int ingestionId) async {
    final data = await _sendJson('GET', '$_base/$ingestionId');
    final missing = (data['missing_parts'] as List<dynamic>? ?? [])
        .map((m) => (
              kind: (m as Map)['kind'] as String,
              sequence: m['sequence'] as int,
            ))
        .toList();
    return IngestionStatus(
      status: data['status'] as String,
      missingParts: missing,
      tripId: data['trip_id'] as int?,
    );
  }

  Future<Map<String, dynamic>> _sendJson(
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
    final decoded = responseBody.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(responseBody) as Map<String, dynamic>;

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded['detail'];
      throw IngestionApiException(
        detail is String ? detail : 'Richiesta ingestion fallita',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  Uri _uri(String path) {
    final base = ApiConstants.baseApiUrl.endsWith('/')
        ? ApiConstants.baseApiUrl
            .substring(0, ApiConstants.baseApiUrl.length - 1)
        : ApiConstants.baseApiUrl;
    return Uri.parse('$base$path');
  }
}
