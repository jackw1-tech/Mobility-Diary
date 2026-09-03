import 'package:diary/model/entities/acquisition/core_payload.dart';
import 'package:diary/model/entities/acquisition/ingestion_models.dart';
import 'package:diary/network/dto/ingestion/active_ingestion_dto.dart';
import 'package:diary/network/dto/ingestion/ingestion_start_result_dto.dart';
import 'package:diary/network/dto/ingestion/ingestion_status_dto.dart';
import 'package:diary/network/dto/ingestion/inline_core_result_dto.dart';
import 'package:diary/network/dto/ingestion/presign_result_dto.dart';
import 'package:diary/network/dto/ingestion/replay_data_dto.dart';
import 'package:diary/utils/date_time_utils.dart';

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
      tripId: dto.tripId,
      mapAvailable: dto.mapAvailable,
    );
  }

  /// Traccia sorgente di un replay, ordinata per timestamp: il backend la
  /// restituisce gia' ordinata, ma l'ordinamento e' un requisito del timer di
  /// replay, non un dettaglio del trasporto.
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

  /// Corpo di POST /ingestion/core-inline. Unico punto in cui il payload core
  /// prende la sua forma wire: prima veniva costruito due volte, una in
  /// TripPackageBuilder per i viaggi live e una in ReplayAcquisitionStrategy
  /// per quelli rigiocati.
  Map<String, dynamic> toCorePayloadJson({
    required String clientSessionId,
    required String deviceId,
    required List<CoreGpsPoint> gpsPoints,
    required List<CoreStateTransition> transitions,
    required int expectedRawParts,
    DateTime? startedAt,
    DateTime? endedAt,
    int? ingestionId,
    DateTime? cutoffSourceTimestamp,
  }) {
    return {
      'app_version': '',
      'client_session_id': clientSessionId,
      if (cutoffSourceTimestamp != null)
        'cutoff_source_timestamp': DateTimeUtils.toUtcIso(
          cutoffSourceTimestamp,
        ),
      'device_id': deviceId,
      'device_platform': '',
      'ended_at': DateTimeUtils.toUtcIsoOrNull(endedAt),
      'expected_raw_parts': expectedRawParts,
      'gps_points': [
        for (final point in gpsPoints) _gpsPointJson(point),
      ],
      if (ingestionId != null) 'ingestion_id': ingestionId,
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
        'reason': transition.reason,
        'sigma': transition.sigma,
        'speed_mps': transition.speedMps,
        'timestamp': DateTimeUtils.toUtcIso(transition.timestamp),
        'to_state': transition.toState,
      };

  InlineCoreResult mapInlineCoreResult(InlineCoreResultDto dto) {
    return InlineCoreResult(
      ingestionId: dto.ingestionId,
      tripId: dto.tripId,
      coreStatus: dto.coreStatus,
      rawStatus: dto.rawStatus,
      mapAvailable: dto.mapAvailable,
    );
  }
}
