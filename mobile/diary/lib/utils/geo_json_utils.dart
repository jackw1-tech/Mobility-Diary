import 'package:latlong2/latlong.dart';

/// Converte una geometry GeoJSON `LineString` in una polilinea di [LatLng].
/// Ritorna una lista vuota per geometry nulle, di tipo diverso o malformate.
/// Funzione pura condivisa da model e DTO che espongono entrambi una
/// geometry grezza (nessuna logica di business, solo trasformazione dati).
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
