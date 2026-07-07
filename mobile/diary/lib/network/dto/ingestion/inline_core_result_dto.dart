import 'package:json_annotation/json_annotation.dart';

part 'inline_core_result_dto.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class InlineCoreResultDto {
  final int ingestionId;
  final int? tripId;
  final String coreStatus;
  final String rawStatus;
  final int gpsPoints;
  final int stateTransitions;
  final int pathPoints;
  final double distanceMeters;
  @JsonKey(defaultValue: false)
  final bool mapAvailable;

  const InlineCoreResultDto({
    required this.ingestionId,
    required this.tripId,
    required this.coreStatus,
    required this.rawStatus,
    required this.gpsPoints,
    required this.stateTransitions,
    required this.pathPoints,
    required this.distanceMeters,
    required this.mapAvailable,
  });

  factory InlineCoreResultDto.fromJson(Map<String, dynamic> json) =>
      _$InlineCoreResultDtoFromJson(json);

  Map<String, dynamic> toJson() => _$InlineCoreResultDtoToJson(this);
}
