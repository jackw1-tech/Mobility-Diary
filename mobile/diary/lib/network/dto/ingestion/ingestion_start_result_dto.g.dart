// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ingestion_start_result_dto.dart';

IngestionStartResultDto _$IngestionStartResultDtoFromJson(
        Map<String, dynamic> json) =>
    IngestionStartResultDto(
      ingestionId: (json['ingestion_id'] as num).toInt(),
      clientSessionId: json['client_session_id'] as String,
      deviceId: json['device_id'] as String,
      recordingStartedAt:
          DateTime.parse(json['recording_started_at'] as String),
      alreadyExists: json['already_exists'] as bool? ?? false,
    );

Map<String, dynamic> _$IngestionStartResultDtoToJson(
        IngestionStartResultDto instance) =>
    <String, dynamic>{
      'ingestion_id': instance.ingestionId,
      'client_session_id': instance.clientSessionId,
      'device_id': instance.deviceId,
      'recording_started_at': instance.recordingStartedAt.toIso8601String(),
      'already_exists': instance.alreadyExists,
    };
