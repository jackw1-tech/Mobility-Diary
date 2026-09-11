import 'package:latlong2/latlong.dart' as ll;

enum RouteMode { walking, cycling, driving }

extension RouteModeProfile on RouteMode {
  /// Nome del profilo Mapbox Directions.
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

/// Risultato di geocoding
class GeocodingPlace {
  final String label;
  final ll.LatLng location;

  const GeocodingPlace({required this.label, required this.location});
}

class RouteAssistantRoute {
  final List<ll.LatLng> points;
  final double distanceMeters;
  final double durationSeconds;

  const RouteAssistantRoute({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });
}

/// Errore delle chiamate Mapbox.
class RouteAssistantException implements Exception {
  final String message;

  const RouteAssistantException(this.message);

  @override
  String toString() => message;
}
