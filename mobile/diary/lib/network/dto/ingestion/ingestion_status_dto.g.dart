// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ingestion_status_dto.dart';

IngestionMissingPartDto _$IngestionMissingPartDtoFromJson(
        Map<String, dynamic> json) =>
    IngestionMissingPartDto(
      kind: json['kind'] as String,
      sequence: (json['sequence'] as num).toInt(),
    );

Map<String, dynamic> _$IngestionMissingPartDtoToJson(
        IngestionMissingPartDto instance) =>
    <String, dynamic>{
      'kind': instance.kind,
      'sequence': instance.sequence,
    };

IngestionStatusDto _$IngestionStatusDtoFromJson(Map<String, dynamic> json) =>
    IngestionStatusDto(
      coreStatus: json['core_status'] as String,
      rawStatus: json['raw_status'] as String,
      missingCoreParts: (json['missing_core_parts'] as List<dynamic>?)
              ?.map((e) =>
                  IngestionMissingPartDto.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      missingRawParts: (json['missing_raw_parts'] as List<dynamic>?)
              ?.map((e) =>
                  IngestionMissingPartDto.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      tripId: (json['trip_id'] as num?)?.toInt(),
      coreIngestionMode:
          json['core_ingestion_mode'] as String? ?? 'LEGACY_PARTS',
      mapAvailable: json['map_available'] as bool? ?? false,
    );

Map<String, dynamic> _$IngestionStatusDtoToJson(IngestionStatusDto instance) =>
    <String, dynamic>{
      'core_status': instance.coreStatus,
      'raw_status': instance.rawStatus,
      'missing_core_parts':
          instance.missingCoreParts.map((e) => e.toJson()).toList(),
      'missing_raw_parts':
          instance.missingRawParts.map((e) => e.toJson()).toList(),
      if (instance.tripId != null) 'trip_id': instance.tripId,
      'core_ingestion_mode': instance.coreIngestionMode,
      'map_available': instance.mapAvailable,
    };
