import 'package:latlong2/latlong.dart';

/// Partiamo dal GeoJson restituito e costruiamo una lista di oggetti LatLng
List<LatLng> latLngsFromGeoJsonLineString(Map<String, dynamic>? geometry) {
  if (geometry == null || geometry['type'] != 'LineString') return const [];

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
