// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'upload_status_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UploadMissingPartDto _$UploadMissingPartDtoFromJson(
        Map<String, dynamic> json) =>
    UploadMissingPartDto(
      sequence: (json['sequence'] as num).toInt(),
    );

Map<String, dynamic> _$UploadMissingPartDtoToJson(
        UploadMissingPartDto instance) =>
    <String, dynamic>{
      'sequence': instance.sequence,
    };

UploadStatusDto _$UploadStatusDtoFromJson(Map<String, dynamic> json) =>
    UploadStatusDto(
      coreStatus: json['core_status'] as String,
      rawStatus: json['raw_status'] as String,
      missingRawParts: (json['missing_raw_parts'] as List<dynamic>?)
              ?.map((e) =>
                  UploadMissingPartDto.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      tripId: (json['trip_id'] as num?)?.toInt(),
      mapAvailable: json['map_available'] as bool? ?? false,
    );

Map<String, dynamic> _$UploadStatusDtoToJson(UploadStatusDto instance) =>
    <String, dynamic>{
      'core_status': instance.coreStatus,
      'raw_status': instance.rawStatus,
      'missing_raw_parts': instance.missingRawParts,
      'trip_id': instance.tripId,
      'map_available': instance.mapAvailable,
    };
