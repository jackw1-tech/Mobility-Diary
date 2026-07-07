enum DiaryEventStatus { enriched, failed, unknown }

class DiaryEvent {
  final DiaryEventStatus status;
  final int? tripId;
  final String? reasonCode;

  const DiaryEvent({
    required this.status,
    this.tripId,
    this.reasonCode,
  });
}
