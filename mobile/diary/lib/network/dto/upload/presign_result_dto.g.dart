// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'presign_result_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PresignResultDto _$PresignResultDtoFromJson(Map<String, dynamic> json) =>
    PresignResultDto(
      objectKey: json['object_key'] as String,
      uploadUrl: json['upload_url'] as String,
      uploadHeaders: (json['upload_headers'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(k, e as String),
          ) ??
          {},
    );

Map<String, dynamic> _$PresignResultDtoToJson(PresignResultDto instance) =>
    <String, dynamic>{
      'object_key': instance.objectKey,
      'upload_url': instance.uploadUrl,
      'upload_headers': instance.uploadHeaders,
    };
