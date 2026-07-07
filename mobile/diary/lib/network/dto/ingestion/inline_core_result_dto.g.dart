// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inline_core_result_dto.dart';

InlineCoreResultDto _$InlineCoreResultDtoFromJson(Map<String, dynamic> json) =>
    InlineCoreResultDto(
      ingestionId: (json['ingestion_id'] as num).toInt(),
      tripId: (json['trip_id'] as num?)?.toInt(),
      coreStatus: json['core_status'] as String,
      rawStatus: json['raw_status'] as String,
      gpsPoints: (json['gps_points'] as num).toInt(),
      stateTransitions: (json['state_transitions'] as num).toInt(),
      pathPoints: (json['path_points'] as num).toInt(),
      distanceMeters: (json['distance_meters'] as num).toDouble(),
      mapAvailable: json['map_available'] as bool? ?? false,
    );

Map<String, dynamic> _$InlineCoreResultDtoToJson(
        InlineCoreResultDto instance) =>
    <String, dynamic>{
      'ingestion_id': instance.ingestionId,
      if (instance.tripId != null) 'trip_id': instance.tripId,
      'core_status': instance.coreStatus,
      'raw_status': instance.rawStatus,
      'gps_points': instance.gpsPoints,
      'state_transitions': instance.stateTransitions,
      'path_points': instance.pathPoints,
      'distance_meters': instance.distanceMeters,
      'map_available': instance.mapAvailable,
    };
