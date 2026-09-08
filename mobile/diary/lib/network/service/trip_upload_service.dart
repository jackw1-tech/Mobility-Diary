import 'package:diary/network/dto/upload/active_upload_dto.dart';
import 'package:diary/network/dto/upload/upload_start_result_dto.dart';
import 'package:diary/network/dto/upload/upload_status_dto.dart';
import 'package:diary/network/dto/upload/inline_core_result_dto.dart';
import 'package:diary/network/dto/upload/presign_result_dto.dart';
import 'package:diary/network/dto/upload/replay_data_dto.dart';

/// Fornisce il bearer token corrente (da AuthRepository). Null se non loggato.
typedef AccessTokenProvider = Future<String?> Function();

class UploadApiException implements Exception {
  final String message;
  final int? statusCode;
  final Map<String, dynamic> body;
  const UploadApiException(
    this.message, {
    this.statusCode,
    this.body = const {},
  });
  @override
  String toString() => message;
}

/// Estrae l'upload attiva dal corpo di un 409 sollevato da
/// [TripUploadService.startUpload]. Sta qui e non nei repository perche'
/// il parsing del JSON di rete e' responsabilita' del layer network: i
/// repository ricevono il DTO e lo convertono in entity con UploadMapper.
ActiveUploadDto? activeUploadFromConflict(UploadApiException error) {
  final active = error.body['active_upload'];
  if (active is! Map) return null;
  return ActiveUploadDto.fromJson(Map<String, dynamic>.from(active));
}

abstract class TripUploadService {
  Future<ActiveUploadDto?> getActiveUpload();

  Future<UploadStartResultDto> startUpload({
    required String clientSessionId,
    required DateTime startedAt,
    required String deviceId,
    int? sourceTripId,
  });

  Future<void> abandonUpload({
    required int uploadId,
    required String deviceId,
  });

  Future<void> heartbeatUpload({
    required int uploadId,
    required String clientSessionId,
    required String deviceId,
  });

  Future<InlineCoreResultDto> postCoreInline({
    required Map<String, dynamic> body,
  });

  Future<PresignResultDto> presignPart(
    int uploadId, {
    required int sequence,
    required String sha256,
  });

  Future<void> uploadPart(
    String uploadUrl,
    List<int> bytes, {
    Map<String, String> headers,
  });

  Future<void> confirmPart(
    int uploadId, {
    required int sequence,
    required String sha256,
  });

  Future<void> completeRawUpload(int uploadId, {required int totalParts});

  Future<UploadStatusDto> getStatus(int uploadId);

  Future<ReplayDataDto> getReplayData(int tripId);

  Future<List<List<double>>> getReplaySensorWindow(
      int tripId, int offsetSeconds);
}
