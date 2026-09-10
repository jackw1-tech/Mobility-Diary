import 'package:diary/model/entities/acquisition/core_payload.dart';
import 'package:diary/model/entities/acquisition/upload_models.dart';
import 'package:diary/network/dto/upload/active_upload_dto.dart';
import 'package:diary/network/dto/upload/upload_start_result_dto.dart';
import 'package:diary/network/dto/upload/upload_status_dto.dart';
import 'package:diary/network/dto/upload/inline_core_result_dto.dart';
import 'package:diary/network/dto/upload/presign_result_dto.dart';
import 'package:diary/network/dto/upload/replay_data_dto.dart';
import 'package:diary/utils/date_time_utils.dart';

class UploadMapper {
  ActiveUpload mapActiveUpload(ActiveUploadDto dto) {
    return ActiveUpload(
      uploadId: dto.uploadId,
      clientSessionId: dto.clientSessionId,
      deviceId: dto.deviceId,
      recordingStartedAt: dto.recordingStartedAt,
      lastSeenAt: dto.lastSeenAt,
    );
  }

  UploadStartResult mapUploadStartResult(UploadStartResultDto dto) {
    return UploadStartResult(
      uploadId: dto.uploadId,
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

  UploadStatus mapUploadStatus(UploadStatusDto dto) {
    return UploadStatus(
      coreStatus: dto.coreStatus,
      rawStatus: dto.rawStatus,
      tripId: dto.tripId,
      mapAvailable: dto.mapAvailable,
    );
  }

  ReplaySource mapReplayData(ReplayDataDto dto) {
    final points = [
      for (final point in dto.gpsPoints)
        CoreGpsPoint(
          timestamp: point.timestamp,
          latitude: point.latitude,
          longitude: point.longitude,
          speedMps: point.speedMps,
          accuracyMeters: point.accuracyMeters,
        ),
    ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final transitions = [
      for (final transition in dto.stateTransitions)
        CoreStateTransition(
          timestamp: transition.timestamp,
          fromState: transition.fromState,
          toState: transition.toState,
        ),
    ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return ReplaySource(
      sourceTripId: dto.sourceTripId,
      points: points,
      transitions: transitions,
    );
  }

  Map<String, dynamic> toCorePayloadJson({
    required String clientSessionId,
    required String deviceId,
    required List<CoreGpsPoint> gpsPoints,
    required List<CoreStateTransition> transitions,
    required int expectedRawParts,
    DateTime? startedAt,
    DateTime? endedAt,
    int? uploadId,
    DateTime? cutoffSourceTimestamp,
  }) {
    return {
      'app_version': '',
      'client_session_id': clientSessionId,
      if (cutoffSourceTimestamp != null)
        'cutoff_source_timestamp': DateTimeUtils.toUtcIso(
          cutoffSourceTimestamp,
        ), // Di al back-end di scartare tutte le finestre har oltre quella data e orario
      'device_id': deviceId,
      'ended_at': DateTimeUtils.toUtcIsoOrNull(endedAt),
      'expected_raw_parts': expectedRawParts,
      'gps_points': [
        for (final point in gpsPoints) _gpsPointJson(point),
      ],
      if (uploadId != null) 'upload_id': uploadId,
      'schema_version': 1,
      'started_at': DateTimeUtils.toUtcIsoOrNull(startedAt),
      'state_transitions': [
        for (final transition in transitions) _transitionJson(transition),
      ],
      'timezone': '',
    };
  }

  Map<String, dynamic> _gpsPointJson(CoreGpsPoint point) => {
        'accuracy_meters': point.accuracyMeters,
        'latitude': point.latitude,
        'longitude': point.longitude,
        'speed_mps': point.speedMps,
        'timestamp': DateTimeUtils.toUtcIso(point.timestamp),
      };

  Map<String, dynamic> _transitionJson(CoreStateTransition transition) => {
        'from_state': transition.fromState,
        'sigma': transition.sigma,
        'speed_mps': transition.speedMps,
        'timestamp': DateTimeUtils.toUtcIso(transition.timestamp),
        'to_state': transition.toState,
      };

  InlineCoreResult mapInlineCoreResult(InlineCoreResultDto dto) {
    return InlineCoreResult(
      uploadId: dto.uploadId,
      tripId: dto.tripId,
      coreStatus: dto.coreStatus,
      rawStatus: dto.rawStatus,
      mapAvailable: dto.mapAvailable,
    );
  }
}
