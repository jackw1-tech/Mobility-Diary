// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'upload_start_result_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UploadStartResultDto _$UploadStartResultDtoFromJson(
        Map<String, dynamic> json) =>
    UploadStartResultDto(
      uploadId: (json['upload_id'] as num).toInt(),
      clientSessionId: json['client_session_id'] as String,
      deviceId: json['device_id'] as String,
      recordingStartedAt:
          DateTime.parse(json['recording_started_at'] as String),
      alreadyExists: json['already_exists'] as bool? ?? false,
    );

Map<String, dynamic> _$UploadStartResultDtoToJson(
        UploadStartResultDto instance) =>
    <String, dynamic>{
      'upload_id': instance.uploadId,
      'client_session_id': instance.clientSessionId,
      'device_id': instance.deviceId,
      'recording_started_at': instance.recordingStartedAt.toIso8601String(),
      'already_exists': instance.alreadyExists,
    };
