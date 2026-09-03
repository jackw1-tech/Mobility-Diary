import 'package:json_annotation/json_annotation.dart';

part 'active_upload_dto.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class ActiveUploadDto {
  final int uploadId;
  final String clientSessionId;
  final String deviceId;
  final DateTime recordingStartedAt;
  final DateTime? lastSeenAt;

  const ActiveUploadDto({
    required this.uploadId,
    required this.clientSessionId,
    required this.deviceId,
    required this.recordingStartedAt,
    this.lastSeenAt,
  });

  factory ActiveUploadDto.fromJson(Map<String, dynamic> json) =>
      _$ActiveUploadDtoFromJson(json);

  Map<String, dynamic> toJson() => _$ActiveUploadDtoToJson(this);
}
