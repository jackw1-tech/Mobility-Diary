// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'active_upload_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ActiveUploadDto _$ActiveUploadDtoFromJson(Map<String, dynamic> json) =>
    ActiveUploadDto(
      uploadId: (json['upload_id'] as num).toInt(),
      clientSessionId: json['client_session_id'] as String,
      deviceId: json['device_id'] as String,
      recordingStartedAt: DateTime.parse(
        json['recording_started_at'] as String,
      ),
      lastSeenAt: json['last_seen_at'] == null
          ? null
          : DateTime.parse(json['last_seen_at'] as String),
    );

Map<String, dynamic> _$ActiveUploadDtoToJson(ActiveUploadDto instance) =>
    <String, dynamic>{
      'upload_id': instance.uploadId,
      'client_session_id': instance.clientSessionId,
      'device_id': instance.deviceId,
      'recording_started_at': instance.recordingStartedAt.toIso8601String(),
      'last_seen_at': instance.lastSeenAt?.toIso8601String(),
    };
