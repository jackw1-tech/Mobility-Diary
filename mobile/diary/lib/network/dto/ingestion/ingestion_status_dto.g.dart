// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ingestion_status_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

IngestionMissingPartDto _$IngestionMissingPartDtoFromJson(
        Map<String, dynamic> json) =>
    IngestionMissingPartDto(
      sequence: (json['sequence'] as num).toInt(),
    );

Map<String, dynamic> _$IngestionMissingPartDtoToJson(
        IngestionMissingPartDto instance) =>
    <String, dynamic>{
      'sequence': instance.sequence,
    };

IngestionStatusDto _$IngestionStatusDtoFromJson(Map<String, dynamic> json) =>
    IngestionStatusDto(
      coreStatus: json['core_status'] as String,
      rawStatus: json['raw_status'] as String,
      missingRawParts: (json['missing_raw_parts'] as List<dynamic>?)
              ?.map((e) =>
                  IngestionMissingPartDto.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      tripId: (json['trip_id'] as num?)?.toInt(),
      mapAvailable: json['map_available'] as bool? ?? false,
    );

Map<String, dynamic> _$IngestionStatusDtoToJson(IngestionStatusDto instance) =>
    <String, dynamic>{
      'core_status': instance.coreStatus,
      'raw_status': instance.rawStatus,
      'missing_raw_parts': instance.missingRawParts,
      'trip_id': instance.tripId,
      'map_available': instance.mapAvailable,
    };
