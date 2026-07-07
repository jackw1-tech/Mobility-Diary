import 'package:json_annotation/json_annotation.dart';

part 'presign_result_dto.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class PresignResultDto {
  final String objectKey;
  final String uploadUrl;
  @JsonKey(defaultValue: {})
  final Map<String, String> uploadHeaders;

  const PresignResultDto({
    required this.objectKey,
    required this.uploadUrl,
    required this.uploadHeaders,
  });

  factory PresignResultDto.fromJson(Map<String, dynamic> json) =>
      _$PresignResultDtoFromJson(json);

  Map<String, dynamic> toJson() => _$PresignResultDtoToJson(this);
}
