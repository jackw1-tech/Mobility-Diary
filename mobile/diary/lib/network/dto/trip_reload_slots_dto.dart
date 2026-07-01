class TripReloadSlotDto {
  final DateTime startedAt;
  final DateTime endedAt;

  const TripReloadSlotDto({
    required this.startedAt,
    required this.endedAt,
  });

  factory TripReloadSlotDto.fromJson(Map<String, dynamic> json) {
    return TripReloadSlotDto(
      startedAt: DateTime.parse(json['started_at'] as String),
      endedAt: DateTime.parse(json['ended_at'] as String),
    );
  }
}

class TripReloadSlotsDto {
  final int sourceTripId;
  final int durationSeconds;
  final List<TripReloadSlotDto> slots;

  const TripReloadSlotsDto({
    required this.sourceTripId,
    required this.durationSeconds,
    required this.slots,
  });

  factory TripReloadSlotsDto.fromJson(Map<String, dynamic> json) {
    final rawSlots = json['slots'] as List<dynamic>? ?? const [];
    return TripReloadSlotsDto(
      sourceTripId: json['source_trip_id'] as int,
      durationSeconds: json['duration_seconds'] as int,
      slots: rawSlots
          .map(
            (slot) => TripReloadSlotDto.fromJson(
              Map<String, dynamic>.from(slot as Map),
            ),
          )
          .toList(growable: false),
    );
  }
}
