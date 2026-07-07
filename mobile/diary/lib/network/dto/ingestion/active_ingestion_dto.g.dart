// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'active_ingestion_dto.dart';

ActiveIngestionDto _$ActiveIngestionDtoFromJson(Map<String, dynamic> json) =>
    ActiveIngestionDto(
      ingestionId: (json['ingestion_id'] as num).toInt(),
      clientSessionId: json['client_session_id'] as String,
      deviceId: json['device_id'] as String,
      recordingStartedAt:
          DateTime.parse(json['recording_started_at'] as String),
      lastSeenAt: json['last_seen_at'] == null
          ? null
          : DateTime.parse(json['last_seen_at'] as String),
    );

Map<String, dynamic> _$ActiveIngestionDtoToJson(ActiveIngestionDto instance) =>
    <String, dynamic>{
      'ingestion_id': instance.ingestionId,
      'client_session_id': instance.clientSessionId,
      'device_id': instance.deviceId,
      'recording_started_at': instance.recordingStartedAt.toIso8601String(),
      if (instance.lastSeenAt != null)
        'last_seen_at': instance.lastSeenAt!.toIso8601String(),
    };
