class TripListItemDto {
  final int id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String status;
  final double? distanceMeters;
  final String note;
  final bool hasTrack;
  final bool isReloadable;
  final bool isDerived;
  final bool canDelete;
  final bool canToggleReloadable;
  final bool canEditNote;

  const TripListItemDto({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.status,
    required this.distanceMeters,
    this.note = '',
    required this.hasTrack,
    this.isReloadable = false,
    this.isDerived = false,
    this.canDelete = false,
    this.canToggleReloadable = false,
    this.canEditNote = false,
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
      note: json['note'] as String? ?? '',
      hasTrack: json['has_track'] as bool? ?? false,
      isReloadable: json['is_reloadable'] as bool? ?? false,
      isDerived: json['is_derived'] as bool? ?? false,
      canDelete: json['can_delete'] as bool? ?? false,
      canToggleReloadable: json['can_toggle_reloadable'] as bool? ?? false,
      canEditNote: json['can_edit_note'] as bool? ?? false,
    );
  }
}
