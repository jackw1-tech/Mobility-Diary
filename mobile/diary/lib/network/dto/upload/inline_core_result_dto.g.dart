// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inline_core_result_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

InlineCoreResultDto _$InlineCoreResultDtoFromJson(Map<String, dynamic> json) =>
    InlineCoreResultDto(
      uploadId: (json['upload_id'] as num).toInt(),
      tripId: (json['trip_id'] as num?)?.toInt(),
      coreStatus: json['core_status'] as String,
      rawStatus: json['raw_status'] as String,
      mapAvailable: json['map_available'] as bool? ?? false,
    );

Map<String, dynamic> _$InlineCoreResultDtoToJson(
  InlineCoreResultDto instance,
) => <String, dynamic>{
  'upload_id': instance.uploadId,
  'trip_id': instance.tripId,
  'core_status': instance.coreStatus,
  'raw_status': instance.rawStatus,
  'map_available': instance.mapAvailable,
};
