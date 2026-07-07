import 'package:json_annotation/json_annotation.dart';

part 'ingestion_start_result_dto.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class IngestionStartResultDto {
  final int ingestionId;
  final String clientSessionId;
  final String deviceId;
  final DateTime recordingStartedAt;

  @JsonKey(defaultValue: false)
  final bool alreadyExists;

  const IngestionStartResultDto({
    required this.ingestionId,
    required this.clientSessionId,
    required this.deviceId,
    required this.recordingStartedAt,
    required this.alreadyExists,
  });

  factory IngestionStartResultDto.fromJson(Map<String, dynamic> json) =>
      _$IngestionStartResultDtoFromJson(json);

  Map<String, dynamic> toJson() => _$IngestionStartResultDtoToJson(this);
}
