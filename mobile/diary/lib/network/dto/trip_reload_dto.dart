class TripReloadDto {
  final int ingestionId;
  final int tripId;
  final String coreStatus;
  final String rawStatus;
  final int gpsPoints;
  final int stateTransitions;
  final int pathPoints;
  final double distanceMeters;
  final bool mapAvailable;

  const TripReloadDto({
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

  factory TripReloadDto.fromJson(Map<String, dynamic> json) {
    return TripReloadDto(
      ingestionId: json['ingestion_id'] as int,
      tripId: json['trip_id'] as int,
      coreStatus: json['core_status'] as String,
      rawStatus: json['raw_status'] as String,
      gpsPoints: json['gps_points'] as int,
      stateTransitions: json['state_transitions'] as int,
      pathPoints: json['path_points'] as int,
      distanceMeters: (json['distance_meters'] as num).toDouble(),
      mapAvailable: json['map_available'] as bool? ?? false,
    );
  }
}
