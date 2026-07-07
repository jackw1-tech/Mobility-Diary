import 'package:diary/features/acquisition/domain/ingestion_models.dart';
import 'package:diary/network/dto/ingestion/active_ingestion_dto.dart';
import 'package:diary/network/dto/ingestion/ingestion_start_result_dto.dart';
import 'package:diary/network/dto/ingestion/ingestion_status_dto.dart';
import 'package:diary/network/dto/ingestion/inline_core_result_dto.dart';
import 'package:diary/network/dto/ingestion/presign_result_dto.dart';

class IngestionMapper {
  ActiveIngestion mapActiveIngestion(ActiveIngestionDto dto) {
    return ActiveIngestion(
      ingestionId: dto.ingestionId,
      clientSessionId: dto.clientSessionId,
      deviceId: dto.deviceId,
      recordingStartedAt: dto.recordingStartedAt,
      lastSeenAt: dto.lastSeenAt,
    );
  }

  IngestionStartResult mapIngestionStartResult(IngestionStartResultDto dto) {
    return IngestionStartResult(
      ingestionId: dto.ingestionId,
      clientSessionId: dto.clientSessionId,
      deviceId: dto.deviceId,
      recordingStartedAt: dto.recordingStartedAt,
      alreadyExists: dto.alreadyExists,
    );
  }

  PresignResult mapPresignResult(PresignResultDto dto) {
    return PresignResult(
      objectKey: dto.objectKey,
      uploadUrl: dto.uploadUrl,
      uploadHeaders: dto.uploadHeaders,
    );
  }

  IngestionStatus mapIngestionStatus(IngestionStatusDto dto) {
    return IngestionStatus(
      coreStatus: dto.coreStatus,
      rawStatus: dto.rawStatus,
      missingCoreParts: dto.missingCoreParts
          .map((e) => (kind: e.kind, sequence: e.sequence))
          .toList(),
      missingRawParts: dto.missingRawParts
          .map((e) => (kind: e.kind, sequence: e.sequence))
          .toList(),
      tripId: dto.tripId,
      coreIngestionMode: dto.coreIngestionMode,
      mapAvailable: dto.mapAvailable,
    );
  }

  InlineCoreResult mapInlineCoreResult(InlineCoreResultDto dto) {
    return InlineCoreResult(
      ingestionId: dto.ingestionId,
      tripId: dto.tripId,
      coreStatus: dto.coreStatus,
      rawStatus: dto.rawStatus,
      gpsPoints: dto.gpsPoints,
      stateTransitions: dto.stateTransitions,
      pathPoints: dto.pathPoints,
      distanceMeters: dto.distanceMeters,
      mapAvailable: dto.mapAvailable,
    );
  }
}
