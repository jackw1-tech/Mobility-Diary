import 'package:diary/network/dto/ingestion/active_ingestion_dto.dart';
import 'package:diary/network/dto/ingestion/ingestion_start_result_dto.dart';
import 'package:diary/network/dto/ingestion/ingestion_status_dto.dart';
import 'package:diary/network/dto/ingestion/inline_core_result_dto.dart';
import 'package:diary/network/dto/ingestion/presign_result_dto.dart';

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

abstract class TripIngestionService {
  Future<ActiveIngestionDto?> getActiveIngestion();

  Future<IngestionStartResultDto> startIngestion({
    required String clientSessionId,
    required DateTime startedAt,
    required String deviceId,
    String devicePlatform,
    int? sourceTripId,
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

  Future<InlineCoreResultDto> postCoreInline({
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

  Future<PresignResultDto> presignPart(
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

  Future<IngestionStatusDto> getStatus(int ingestionId);

  Future<Map<String, dynamic>> getReplayData(int tripId);

  Future<List<List<double>>> getReplaySensorWindow(
      int tripId, int offsetSeconds);
}
