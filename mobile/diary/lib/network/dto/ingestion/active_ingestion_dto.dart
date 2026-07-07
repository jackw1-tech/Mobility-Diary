import 'package:json_annotation/json_annotation.dart';

part 'active_ingestion_dto.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class ActiveIngestionDto {
  final int ingestionId;
  final String clientSessionId;
  final String deviceId;
  final DateTime recordingStartedAt;
  final DateTime? lastSeenAt;

  const ActiveIngestionDto({
    required this.ingestionId,
    required this.clientSessionId,
    required this.deviceId,
    required this.recordingStartedAt,
    this.lastSeenAt,
  });

  factory ActiveIngestionDto.fromJson(Map<String, dynamic> json) =>
      _$ActiveIngestionDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ActiveIngestionDtoToJson(this);
}
