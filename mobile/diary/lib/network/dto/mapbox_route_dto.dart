class MapboxRouteDto {
  final num? distanceMeters;
  final num? durationSeconds;

  final List<dynamic>? coordinates;

  const MapboxRouteDto({
    this.distanceMeters,
    this.durationSeconds,
    this.coordinates,
  });

  factory MapboxRouteDto.fromJson(Map<String, dynamic> json) {
    final geometry = json['geometry'];
    return MapboxRouteDto(
      distanceMeters: json['distance'] as num?,
      durationSeconds: json['duration'] as num?,
      coordinates: geometry is Map
          ? geometry['coordinates'] as List<dynamic>?
          : null,
    );
  }
}
