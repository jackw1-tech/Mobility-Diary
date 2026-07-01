import 'dart:convert';
import 'dart:io';

import 'package:diary/features/route_assistant/domain/route_assistant_domain.dart';
import 'package:latlong2/latlong.dart' as ll;

/// Assistente di percorso: geocoding e routing via API Mapbox chiamate
/// direttamente dal client (il token Mapbox e' gia' presente nell'app).
abstract class RouteAssistantService {
  /// Cerca luoghi per testo libero. `proximity` ordina i risultati vicino a un
  /// punto (tipicamente la posizione corrente).
  Future<List<GeocodingPlace>> searchPlaces(String query, {ll.LatLng? proximity});

  /// Percorso da `from` a `to` col profilo della modalita' scelta. Restituisce
  /// i vertici della geometria (lon/lat), gia' pronti da disegnare sulla mappa.
  Future<List<ll.LatLng>> fetchRoute({
    required ll.LatLng from,
    required ll.LatLng to,
    required RouteMode mode,
  });
}

class MapboxRouteAssistantService implements RouteAssistantService {
  final String _token;
  final HttpClient _client;

  MapboxRouteAssistantService({
    String token = const String.fromEnvironment('MAPBOX_ACCESS_TOKEN'),
    HttpClient? client,
  })  : _token = token,
        _client = client ?? HttpClient();

  @override
  Future<List<GeocodingPlace>> searchPlaces(
    String query, {
    ll.LatLng? proximity,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final params = {
      'access_token': _token,
      'limit': '5',
      if (proximity != null)
        'proximity': '${proximity.longitude},${proximity.latitude}',
    };
    // Path non pre-codificato: Uri.https percent-codifica gli spazi una volta
    // sola (pre-codificarlo darebbe doppio encoding e ricerche errate).
    final uri = Uri.https(
      'api.mapbox.com',
      '/geocoding/v5/mapbox.places/$trimmed.json',
      params,
    );
    final data = await _getJson(uri);
    final features = data['features'];
    if (features is! List) return const [];
    return features
        .map(_placeFromFeature)
        .whereType<GeocodingPlace>()
        .toList(growable: false);
  }

  @override
  Future<List<ll.LatLng>> fetchRoute({
    required ll.LatLng from,
    required ll.LatLng to,
    required RouteMode mode,
  }) async {
    final coords =
        '${from.longitude},${from.latitude};${to.longitude},${to.latitude}';
    final uri = Uri.https(
      'api.mapbox.com',
      '/directions/v5/mapbox/${mode.mapboxProfile}/$coords',
      {
        'access_token': _token,
        'geometries': 'geojson',
        'overview': 'full',
      },
    );
    final data = await _getJson(uri);
    final routes = data['routes'];
    if (routes is! List || routes.isEmpty) {
      throw const RouteAssistantException('Nessun percorso trovato');
    }
    final coordinates = routes.first['geometry']?['coordinates'];
    if (coordinates is! List) {
      throw const RouteAssistantException('Geometria percorso non valida');
    }
    return coordinates
        .map(_latLngFromCoordinate)
        .whereType<ll.LatLng>()
        .toList(growable: false);
  }

  GeocodingPlace? _placeFromFeature(dynamic feature) {
    if (feature is! Map) return null;
    final location = _latLngFromCoordinate(feature['center']);
    if (location == null) return null;
    final label = feature['place_name'];
    return GeocodingPlace(
      label: label is String ? label : '',
      location: location,
    );
  }

  ll.LatLng? _latLngFromCoordinate(dynamic coordinate) {
    if (coordinate is! List || coordinate.length < 2) return null;
    final lon = coordinate[0];
    final lat = coordinate[1];
    if (lon is! num || lat is! num) return null;
    return ll.LatLng(lat.toDouble(), lon.toDouble());
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    if (_token.isEmpty) {
      throw const RouteAssistantException('Token Mapbox non configurato');
    }
    final request = await _client.getUrl(uri);
    final response = await request.close().timeout(const Duration(seconds: 30));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RouteAssistantException(
        'Richiesta Mapbox fallita (HTTP ${response.statusCode})',
      );
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const RouteAssistantException('Risposta Mapbox non valida');
    }
    return Map<String, dynamic>.from(decoded);
  }
}
