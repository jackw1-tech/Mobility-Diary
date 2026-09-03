import 'package:json_annotation/json_annotation.dart';

part 'inline_core_result_dto.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class InlineCoreResultDto {
  final int uploadId;
  final int? tripId;
  final String coreStatus;
  final String rawStatus;
  @JsonKey(defaultValue: false)
  final bool mapAvailable;

  const InlineCoreResultDto({
    required this.uploadId,
    required this.tripId,
    required this.coreStatus,
    required this.rawStatus,
    required this.mapAvailable,
  });

  factory InlineCoreResultDto.fromJson(Map<String, dynamic> json) =>
      _$InlineCoreResultDtoFromJson(json);

  Map<String, dynamic> toJson() => _$InlineCoreResultDtoToJson(this);
}
