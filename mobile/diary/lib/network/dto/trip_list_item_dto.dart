class TripListItemDto {
  final int id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String status;
  final double? distanceMeters;
  final bool hasTrack;

  const TripListItemDto({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.status,
    required this.distanceMeters,
    required this.hasTrack,
  });

  factory TripListItemDto.fromJson(Map<String, dynamic> json) {
    return TripListItemDto(
      id: json['id'] as int,
      startedAt: DateTime.parse(json['started_at'] as String).toUtc(),
      endedAt: json['ended_at'] == null
          ? null
          : DateTime.parse(json['ended_at'] as String).toUtc(),
      status: json['status'] as String? ?? '',
      distanceMeters: (json['distance_meters'] as num?)?.toDouble(),
      hasTrack: json['has_track'] as bool? ?? false,
    );
  }
}
