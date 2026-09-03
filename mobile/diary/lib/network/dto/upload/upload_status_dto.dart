import 'package:json_annotation/json_annotation.dart';

part 'upload_status_dto.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class UploadMissingPartDto {
  final int sequence;

  const UploadMissingPartDto({
    required this.sequence,
  });

  factory UploadMissingPartDto.fromJson(Map<String, dynamic> json) =>
      _$UploadMissingPartDtoFromJson(json);

  Map<String, dynamic> toJson() => _$UploadMissingPartDtoToJson(this);
}

@JsonSerializable(fieldRename: FieldRename.snake)
class UploadStatusDto {
  final String coreStatus;
  final String rawStatus;

  @JsonKey(defaultValue: [])
  final List<UploadMissingPartDto> missingRawParts;

  final int? tripId;

  @JsonKey(defaultValue: false)
  final bool mapAvailable;

  const UploadStatusDto({
    required this.coreStatus,
    required this.rawStatus,
    required this.missingRawParts,
    this.tripId,
    required this.mapAvailable,
  });

  factory UploadStatusDto.fromJson(Map<String, dynamic> json) =>
      _$UploadStatusDtoFromJson(json);

  Map<String, dynamic> toJson() => _$UploadStatusDtoToJson(this);
}
