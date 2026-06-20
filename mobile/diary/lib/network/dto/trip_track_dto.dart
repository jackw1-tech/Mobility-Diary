import 'package:latlong2/latlong.dart';

class TripTrackDto {
  final int tripId;
  final int pointCount;
  final double distanceMeters;
  final Map<String, dynamic>? geojson;
  final List<double>? bbox;

  const TripTrackDto({
    required this.tripId,
    required this.pointCount,
    required this.distanceMeters,
    required this.geojson,
    this.bbox,
  });

  factory TripTrackDto.fromJson(Map<String, dynamic> json) {
    return TripTrackDto(
      tripId: json['trip_id'] as int,
      pointCount: json['point_count'] as int? ?? 0,
      distanceMeters: (json['distance_meters'] as num? ?? 0).toDouble(),
      geojson: json['geojson'] == null
          ? null
          : Map<String, dynamic>.from(json['geojson'] as Map<dynamic, dynamic>),
      bbox: (json['bbox'] as List<dynamic>?)
          ?.map((value) => (value as num).toDouble())
          .toList(growable: false),
    );
  }

  List<LatLng> get points {
    final geometry = geojson;
    if (geometry == null || geometry['type'] != 'LineString') {
      return const [];
    }

    final coordinates = geometry['coordinates'];
    if (coordinates is! List) return const [];

    return [
      for (final coordinate in coordinates)
        if (coordinate is List && coordinate.length >= 2)
          LatLng(
            (coordinate[1] as num).toDouble(),
            (coordinate[0] as num).toDouble(),
          ),
    ];
  }
}
