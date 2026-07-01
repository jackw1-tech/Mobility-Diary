import 'package:latlong2/latlong.dart' as ll;

/// Modalita' di mobilita' che guida il profilo Mapbox Directions.
enum RouteMode { walking, cycling, driving }

extension RouteModeProfile on RouteMode {
  /// Nome del profilo Mapbox Directions (`mapbox/{profilo}`).
  String get mapboxProfile {
    switch (this) {
      case RouteMode.walking:
        return 'walking';
      case RouteMode.cycling:
        return 'cycling';
      case RouteMode.driving:
        return 'driving';
    }
  }
}

/// Risultato di geocoding: un luogo con etichetta leggibile e coordinate.
class GeocodingPlace {
  final String label;
  final ll.LatLng location;

  const GeocodingPlace({required this.label, required this.location});
}

/// Errore delle chiamate Mapbox (geocoding / directions).
class RouteAssistantException implements Exception {
  final String message;

  const RouteAssistantException(this.message);

  @override
  String toString() => message;
}
