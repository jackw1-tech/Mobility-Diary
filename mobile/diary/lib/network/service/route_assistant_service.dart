import 'dart:convert';
import 'dart:io';

import 'package:diary/model/entities/route_assistant/route_assistant_domain.dart';
import 'package:diary/network/dto/geocoding_feature_dto.dart';
import 'package:diary/network/dto/mapbox_route_dto.dart';
import 'package:latlong2/latlong.dart' as ll;

/// Assistente di percorso: geocoding e routing via API Mapbox chiamate
/// direttamente dal client (il token Mapbox e' gia' presente nell'app).
///
/// Provider layer (Pine): restituisce sempre DTO grezzi. La trasformazione in
/// model di dominio e' compito esclusivo di [RouteAssistantMapper].
abstract class RouteAssistantService {
  /// Cerca luoghi per testo libero. `proximity` ordina i risultati vicino a un
  /// punto (tipicamente la posizione corrente).
  Future<List<GeocodingFeatureDto>> searchPlaces(
    String query, {
    ll.LatLng? proximity,
  });

  /// Percorso da `from` a `to` col profilo della modalita' scelta. Restituisce
  /// il primo percorso Mapbox grezzo, o null se nessuno trovato.
  Future<MapboxRouteDto?> fetchRoute({
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
  Future<List<GeocodingFeatureDto>> searchPlaces(
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
    final uri = Uri.https(
      'api.mapbox.com',
      '/geocoding/v5/mapbox.places/$trimmed.json',
      params,
    );
    final data = await _getJson(uri);
    final features = data['features'];
    if (features is! List) return const [];
    return features
        .whereType<Map>()
        .map((feature) =>
            GeocodingFeatureDto.fromJson(Map<String, dynamic>.from(feature)))
        .toList(growable: false);
  }

  @override
  Future<MapboxRouteDto?> fetchRoute({
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
    if (routes is! List || routes.isEmpty) return null;
    final route = routes.first;
    if (route is! Map) return null;
    return MapboxRouteDto.fromJson(Map<String, dynamic>.from(route));
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
