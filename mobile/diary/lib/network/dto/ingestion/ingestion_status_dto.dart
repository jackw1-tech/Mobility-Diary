import 'package:json_annotation/json_annotation.dart';

part 'ingestion_status_dto.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class IngestionMissingPartDto {
  final String kind;
  final int sequence;

  const IngestionMissingPartDto({
    required this.kind,
    required this.sequence,
  });

  factory IngestionMissingPartDto.fromJson(Map<String, dynamic> json) =>
      _$IngestionMissingPartDtoFromJson(json);

  Map<String, dynamic> toJson() => _$IngestionMissingPartDtoToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class IngestionStatusDto {
  final String coreStatus;
  final String rawStatus;

  @JsonKey(defaultValue: [])
  final List<IngestionMissingPartDto> missingCoreParts;

  @JsonKey(defaultValue: [])
  final List<IngestionMissingPartDto> missingRawParts;

  final int? tripId;

  @JsonKey(defaultValue: 'LEGACY_PARTS')
  final String coreIngestionMode;

  @JsonKey(defaultValue: false)
  final bool mapAvailable;

  const IngestionStatusDto({
    required this.coreStatus,
    required this.rawStatus,
    required this.missingCoreParts,
    required this.missingRawParts,
    this.tripId,
    required this.coreIngestionMode,
    required this.mapAvailable,
  });

  factory IngestionStatusDto.fromJson(Map<String, dynamic> json) =>
      _$IngestionStatusDtoFromJson(json);

  Map<String, dynamic> toJson() => _$IngestionStatusDtoToJson(this);
}
