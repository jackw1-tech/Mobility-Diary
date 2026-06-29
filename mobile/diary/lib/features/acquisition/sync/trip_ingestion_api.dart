import 'dart:convert';
import 'dart:io';

import 'package:diary/other/contants/api_contants.dart';

/// Fornisce il bearer token corrente (da AuthRepository). Null se non loggato.
typedef AccessTokenProvider = Future<String?> Function();

class IngestionApiException implements Exception {
  final String message;
  final int? statusCode;
  final Map<String, dynamic> body;
  const IngestionApiException(
    this.message, {
    this.statusCode,
    this.body = const {},
  });
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
  final String coreStatus;
  final String rawStatus;
  final List<({String kind, int sequence})> missingCoreParts;
  final List<({String kind, int sequence})> missingRawParts;
  final int? tripId;
  final String coreIngestionMode;
  final bool mapAvailable;

  const IngestionStatus({
    required this.coreStatus,
    required this.rawStatus,
    required this.missingCoreParts,
    required this.missingRawParts,
    this.tripId,
    this.coreIngestionMode = 'LEGACY_PARTS',
    this.mapAvailable = false,
  });

  bool get isCoreCompleted => coreStatus == 'COMPLETED';
  bool get isCoreFailedFinal => coreStatus == 'FAILED_FINAL';
  bool get isRawDone => rawStatus == 'COMPLETED';
  bool get isRawFailedFinal => rawStatus == 'FAILED_FINAL';
  bool get isRawBackendProcessing =>
      rawStatus == 'QUEUED' ||
      rawStatus == 'PROCESSING' ||
      rawStatus == 'FAILED_RETRYABLE';
  bool get canCompleteRaw => rawStatus == 'RECEIVED';

  bool get isCoreBackendProcessing {
    return coreStatus == 'QUEUED' ||
        coreStatus == 'PROCESSING' ||
        coreStatus == 'FAILED_RETRYABLE';
  }

  bool get canReceiveCoreParts =>
      coreStatus == 'PENDING' ||
      coreStatus == 'RECEIVING' ||
      coreStatus == 'RECEIVED';

  bool get canReceiveRawParts =>
      rawStatus == 'PENDING' || rawStatus == 'RECEIVING';
}

class InlineCoreResult {
  final int ingestionId;
  final int? tripId;
  final String coreStatus;
  final String rawStatus;
  final int gpsPoints;
  final int stateTransitions;
  final int pathPoints;
  final double distanceMeters;
  final bool mapAvailable;

  const InlineCoreResult({
    required this.ingestionId,
    required this.tripId,
    required this.coreStatus,
    required this.rawStatus,
    required this.gpsPoints,
    required this.stateTransitions,
    required this.pathPoints,
    required this.distanceMeters,
    required this.mapAvailable,
  });

  bool get isCoreCompleted => coreStatus == 'COMPLETED';
  bool get isCoreFailedFinal => coreStatus == 'FAILED_FINAL';
  bool get isCoreBackendProcessing {
    return coreStatus == 'QUEUED' ||
        coreStatus == 'PROCESSING' ||
        coreStatus == 'FAILED_RETRYABLE';
  }

  bool get isRawDone => rawStatus == 'COMPLETED';
  bool get isRawFailedFinal => rawStatus == 'FAILED_FINAL';
  bool get isRawBackendProcessing =>
      rawStatus == 'QUEUED' ||
      rawStatus == 'PROCESSING' ||
      rawStatus == 'FAILED_RETRYABLE';
  bool get canCompleteRaw => rawStatus == 'RECEIVED';
  bool get canReceiveRawParts =>
      rawStatus == 'PENDING' || rawStatus == 'RECEIVING';
}

class IngestionStartResult {
  final int ingestionId;
  final String clientSessionId;
  final String deviceId;
  final DateTime recordingStartedAt;
  final bool alreadyExists;

  const IngestionStartResult({
    required this.ingestionId,
    required this.clientSessionId,
    required this.deviceId,
    required this.recordingStartedAt,
    required this.alreadyExists,
  });
}

class ActiveIngestion {
  final int ingestionId;
  final String clientSessionId;
  final String deviceId;
  final DateTime recordingStartedAt;
  final DateTime? lastSeenAt;

  const ActiveIngestion({
    required this.ingestionId,
    required this.clientSessionId,
    required this.deviceId,
    required this.recordingStartedAt,
    this.lastSeenAt,
  });

  factory ActiveIngestion.fromJson(Map<String, dynamic> data) {
    final lastSeenAt = data['last_seen_at'] as String?;
    return ActiveIngestion(
      ingestionId: data['ingestion_id'] as int,
      clientSessionId: data['client_session_id'] as String,
      deviceId: data['device_id'] as String,
      recordingStartedAt:
          DateTime.parse(data['recording_started_at'] as String).toUtc(),
      lastSeenAt:
          lastSeenAt == null ? null : DateTime.parse(lastSeenAt).toUtc(),
    );
  }
}

/// Client REST dell'ingestione asincrona. Astratto per poter essere mockato
/// nei test della coda di sync.
abstract class TripIngestionApi {
  Future<ActiveIngestion?> getActiveIngestion();

  Future<IngestionStartResult> startIngestion({
    required String clientSessionId,
    required DateTime startedAt,
    required String deviceId,
    String devicePlatform,
  });

  Future<void> abandonIngestion({
    required int ingestionId,
    required String deviceId,
  });

  Future<void> heartbeatIngestion({
    required int ingestionId,
    required String clientSessionId,
    required String deviceId,
  });

  Future<InlineCoreResult> postCoreInline({
    required Map<String, dynamic> body,
  });

  Future<int> createIngestion({
    required String clientSessionId,
    required Map<String, int> expectedCoreParts,
    required Map<String, int> expectedRawParts,
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

  Future<void> completeCoreIngestion(int ingestionId,
      {required int totalParts});

  Future<void> completeRawIngestion(int ingestionId, {required int totalParts});

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
  Future<ActiveIngestion?> getActiveIngestion() async {
    try {
      final data = await _sendJson('GET', '$_base/active');
      return ActiveIngestion.fromJson(data);
    } on IngestionApiException catch (e) {
      if (e.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<IngestionStartResult> startIngestion({
    required String clientSessionId,
    required DateTime startedAt,
    required String deviceId,
    String devicePlatform = '',
  }) async {
    final data = await _sendJson('POST', '$_base/start', body: {
      'client_session_id': clientSessionId,
      'schema_version': 1,
      'started_at': startedAt.toUtc().toIso8601String(),
      'device_id': deviceId,
      'device_platform': devicePlatform,
    });
    return IngestionStartResult(
      ingestionId: data['ingestion_id'] as int,
      clientSessionId: data['client_session_id'] as String,
      deviceId: data['device_id'] as String,
      recordingStartedAt:
          DateTime.parse(data['recording_started_at'] as String).toUtc(),
      alreadyExists: data['already_exists'] as bool? ?? false,
    );
  }

  @override
  Future<void> abandonIngestion({
    required int ingestionId,
    required String deviceId,
  }) async {
    await _sendJson(
      'POST',
      '$_base/$ingestionId/abandon',
      body: {'device_id': deviceId},
    );
  }

  @override
  Future<void> heartbeatIngestion({
    required int ingestionId,
    required String clientSessionId,
    required String deviceId,
  }) async {
    await _sendJson(
      'POST',
      '$_base/$ingestionId/heartbeat',
      body: {
        'client_session_id': clientSessionId,
        'device_id': deviceId,
      },
    );
  }

  @override
  Future<InlineCoreResult> postCoreInline({
    required Map<String, dynamic> body,
  }) async {
    final data = await _sendJson('POST', '$_base/core', body: body);
    return InlineCoreResult(
      ingestionId: data['ingestion_id'] as int,
      tripId: data['trip_id'] as int?,
      coreStatus: data['core_status'] as String,
      rawStatus: data['raw_status'] as String,
      gpsPoints: data['gps_points'] as int,
      stateTransitions: data['state_transitions'] as int,
      pathPoints: data['path_points'] as int,
      distanceMeters: (data['distance_meters'] as num).toDouble(),
      mapAvailable: data['map_available'] as bool? ?? false,
    );
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
    final data = await _sendJson('POST', _base, body: {
      'client_session_id': clientSessionId,
      'schema_version': 1,
      'started_at': startedAt?.toUtc().toIso8601String(),
      'ended_at': endedAt?.toUtc().toIso8601String(),
      'device_id': deviceId,
      'device_platform': devicePlatform,
      'expected_core_parts': expectedCoreParts,
      'expected_raw_parts': expectedRawParts,
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
  Future<void> completeCoreIngestion(
    int ingestionId, {
    required int totalParts,
  }) async {
    await _sendJson(
      'POST',
      '$_base/$ingestionId/complete-core',
      body: {'total_parts': totalParts},
    );
  }

  @override
  Future<void> completeRawIngestion(
    int ingestionId, {
    required int totalParts,
  }) async {
    await _sendJson(
      'POST',
      '$_base/$ingestionId/complete-raw',
      body: {'total_parts': totalParts},
    );
  }

  @override
  Future<IngestionStatus> getStatus(int ingestionId) async {
    final data = await _sendJson('GET', '$_base/$ingestionId');
    List<({String kind, int sequence})> parseParts(String key) {
      return (data[key] as List<dynamic>? ?? [])
          .map((m) => (
                kind: (m as Map)['kind'] as String,
                sequence: m['sequence'] as int,
              ))
          .toList();
    }

    return IngestionStatus(
      coreStatus: data['core_status'] as String,
      rawStatus: data['raw_status'] as String,
      missingCoreParts: parseParts('missing_core_parts'),
      missingRawParts: parseParts('missing_raw_parts'),
      tripId: data['trip_id'] as int?,
      coreIngestionMode:
          data['core_ingestion_mode'] as String? ?? 'LEGACY_PARTS',
      mapAvailable: data['map_available'] as bool? ?? false,
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
        body: decoded,
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
