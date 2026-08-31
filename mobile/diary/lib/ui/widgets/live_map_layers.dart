import 'dart:convert';

import 'package:diary/theme/color_palette.dart';
import 'package:diary/ui/widgets/route_assistant_controls.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Possiede i source/layer Mapbox della mappa live (percorso in
/// registrazione, percorso del Route Assistant, marker di replay) e le
/// relative operazioni di install/update. Costruita solo dopo che lo style
/// e' caricato: la sua sola esistenza significa "pronta a disegnare".
class LiveMapLayers {
  LiveMapLayers._(this._map);

  static const String _liveRouteSourceId = 'live-route-source';
  static const String _liveRouteCasingLayerId = 'live-route-casing';
  static const String _liveRouteLayerId = 'live-route-line';
  static const String _replayMarkerSourceId = 'live-replay-position-source';
  static const String _replayMarkerHaloLayerId = 'live-replay-position-halo';
  static const String _replayMarkerDotLayerId = 'live-replay-position-dot';
  static const String _assistantRouteSourceId = 'route-assistant-source';
  static const String _assistantRouteLayerId = 'route-assistant-line';

  final MapboxMap _map;

  /// Installa tutti i source/layer sullo style appena caricato.
  static Future<LiveMapLayers> install(MapboxMap map) async {
    final layers = LiveMapLayers._(map);
    await layers._installLiveRouteLayer();
    await layers._installReplayMarkerLayer();
    await layers._installAssistantRouteLayer();
    return layers;
  }

  Future<void> _installLiveRouteLayer() async {
    await _map.style.addSource(GeoJsonSource(
      id: _liveRouteSourceId,
      data: _lineGeoJson(const []),
    ));
    await _map.style.addLayer(LineLayer(
      id: _liveRouteCasingLayerId,
      sourceId: _liveRouteSourceId,
      lineColor: ColorPalette.surface.toARGB32(),
      lineWidth: 8.0,
      lineJoin: LineJoin.ROUND,
      lineCap: LineCap.ROUND,
    ));
    await _map.style.addLayer(LineLayer(
      id: _liveRouteLayerId,
      sourceId: _liveRouteSourceId,
      lineColor: ColorPalette.primary.toARGB32(),
      lineWidth: 4.5,
      lineJoin: LineJoin.ROUND,
      lineCap: LineCap.ROUND,
    ));
  }

  Future<void> _installAssistantRouteLayer() async {
    await _map.style.addSource(GeoJsonSource(
      id: _assistantRouteSourceId,
      data: _lineGeoJson(const []),
    ));
    await _map.style.addLayer(LineLayer(
      id: _assistantRouteLayerId,
      sourceId: _assistantRouteSourceId,
      lineColor: routeAssistantRouteColor.toARGB32(),
      lineWidth: 5.0,
      lineJoin: LineJoin.ROUND,
      lineCap: LineCap.ROUND,
    ));
  }

  Future<void> _installReplayMarkerLayer() async {
    await _map.style.addSource(GeoJsonSource(
      id: _replayMarkerSourceId,
      data: _pointsGeoJson(const []),
    ));
    await _map.style.addLayer(CircleLayer(
      id: _replayMarkerHaloLayerId,
      sourceId: _replayMarkerSourceId,
      circleColor: ColorPalette.primary.toARGB32(),
      circleOpacity: 0.22,
      circleRadius: 18,
    ));
    await _map.style.addLayer(CircleLayer(
      id: _replayMarkerDotLayerId,
      sourceId: _replayMarkerSourceId,
      circleColor: ColorPalette.primary.toARGB32(),
      circleRadius: 8,
      circleStrokeColor: ColorPalette.surface.toARGB32(),
      circleStrokeWidth: 3,
    ));
  }

  Future<void> redrawRoute(List<ll.LatLng> points) => _map.style
      .setStyleSourceProperty(_liveRouteSourceId, 'data', _lineGeoJson(points));

  Future<void> updateAssistantRoute(List<ll.LatLng> points) =>
      _map.style.setStyleSourceProperty(
        _assistantRouteSourceId,
        'data',
        _lineGeoJson(points),
      );

  Future<void> updateReplayMarker({
    required bool isReplay,
    required ll.LatLng? latest,
  }) =>
      _map.style.setStyleSourceProperty(
        _replayMarkerSourceId,
        'data',
        _pointsGeoJson(isReplay && latest != null ? [latest] : const []),
      );

  static String _lineGeoJson(List<ll.LatLng> points) {
    return jsonEncode({
      'type': 'FeatureCollection',
      'features': points.length < 2
          ? const []
          : [
              {
                'type': 'Feature',
                'geometry': {
                  'type': 'LineString',
                  'coordinates': [
                    for (final p in points) [p.longitude, p.latitude],
                  ],
                },
                'properties': const {},
              },
            ],
    });
  }

  static String _pointsGeoJson(List<ll.LatLng> points) {
    return jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        for (final p in points)
          {
            'type': 'Feature',
            'geometry': {
              'type': 'Point',
              'coordinates': [p.longitude, p.latitude],
            },
            'properties': const {},
          },
      ],
    });
  }
}
