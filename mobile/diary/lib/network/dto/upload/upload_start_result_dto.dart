import 'package:json_annotation/json_annotation.dart';

part 'upload_start_result_dto.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class UploadStartResultDto {
  final int uploadId;
  final String clientSessionId;
  final String deviceId;
  final DateTime recordingStartedAt;

  @JsonKey(defaultValue: false)
  final bool alreadyExists;

  const UploadStartResultDto({
    required this.uploadId,
    required this.clientSessionId,
    required this.deviceId,
    required this.recordingStartedAt,
    required this.alreadyExists,
  });

  factory UploadStartResultDto.fromJson(Map<String, dynamic> json) =>
      _$UploadStartResultDtoFromJson(json);

  Map<String, dynamic> toJson() => _$UploadStartResultDtoToJson(this);
}
