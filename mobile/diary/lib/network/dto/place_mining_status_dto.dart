class PlaceMiningStatusDto {
  final String status;
  final DateTime? requestedAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final String errorMessage;
  final bool rerunRequested;

  const PlaceMiningStatusDto({
    required this.status,
    this.requestedAt,
    this.startedAt,
    this.finishedAt,
    this.errorMessage = '',
    this.rerunRequested = false,
  });

  bool get isActionable => status == 'SUCCEEDED';
  bool get isPending => status == 'PENDING';
  bool get isRunning => status == 'RUNNING';
  bool get isFailed => status == 'FAILED';

  factory PlaceMiningStatusDto.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(String key) {
      final value = json[key] as String?;
      return value == null || value.isEmpty ? null : DateTime.parse(value);
    }

    return PlaceMiningStatusDto(
      status: json['status'] as String? ?? 'IDLE',
      requestedAt: parseDate('requested_at'),
      startedAt: parseDate('started_at'),
      finishedAt: parseDate('finished_at'),
      errorMessage: json['error_message'] as String? ?? '',
      rerunRequested: json['rerun_requested'] as bool? ?? false,
    );
  }
}
