import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:diary/ui/widgets/category_marker_icons.dart';
import 'package:diary/ui/widgets/route_assistant_controls.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class LabeledPoint {
  final ll.LatLng position;
  final String label;
  final String category;

  const LabeledPoint({
    required this.position,
    required this.label,
    required this.category,
  });
}

class LiveMapLayers {
  static const String _liveRouteSourceId = 'live-route-source';
  static const String _liveRouteCasingLayerId = 'live-route-casing';
  static const String _liveRouteLayerId = 'live-route-line';
  static const String _replayMarkerSourceId = 'live-replay-position-source';
  static const String _replayMarkerHaloLayerId = 'live-replay-position-halo';
  static const String _replayMarkerDotLayerId = 'live-replay-position-dot';
  static const String _assistantRouteSourceId = 'route-assistant-source';
  static const String _assistantRouteLayerId = 'route-assistant-line';
  static const String _habitualPlacesSourceId = 'live-habitual-places-source';
  static const String _habitualPlacesLabelLayerId =
      'live-habitual-places-label';
  static const int _categoryIconRenderSize = 96;

  final MapboxMap _map;
  final int _primaryColor;
  final int _surfaceColor;
  bool _habitualPlacesReady = false;

  LiveMapLayers._(
    this._map, {
    required int primaryColor,
    required int surfaceColor,
  }) : _primaryColor = primaryColor,
       _surfaceColor = surfaceColor;

  static Future<LiveMapLayers> install(
    MapboxMap map, {
    required Color primary,
    required Color surface,
  }) async {
    final layers = LiveMapLayers._(
      map,
      primaryColor: primary.toARGB32(),
      surfaceColor: surface.toARGB32(),
    );
    await layers._installLiveRouteLayer();
    await layers._installReplayMarkerLayer();
    await layers._installAssistantRouteLayer();
    await layers._installHabitualPlacesLayer();
    return layers;
  }

  Future<void> _installLiveRouteLayer() async {
    await _map.style.addSource(
      GeoJsonSource(id: _liveRouteSourceId, data: _lineGeoJson(const [])),
    );
    await _map.style.addLayer(
      LineLayer(
        id: _liveRouteCasingLayerId,
        sourceId: _liveRouteSourceId,
        lineColor: _surfaceColor,
        lineWidth: 8.0,
        lineJoin: LineJoin.ROUND,
        lineCap: LineCap.ROUND,
      ),
    );
    await _map.style.addLayer(
      LineLayer(
        id: _liveRouteLayerId,
        sourceId: _liveRouteSourceId,
        lineColor: _primaryColor,
        lineWidth: 4.5,
        lineJoin: LineJoin.ROUND,
        lineCap: LineCap.ROUND,
      ),
    );
  }

  Future<void> _installAssistantRouteLayer() async {
    await _map.style.addSource(
      GeoJsonSource(id: _assistantRouteSourceId, data: _lineGeoJson(const [])),
    );
    await _map.style.addLayer(
      LineLayer(
        id: _assistantRouteLayerId,
        sourceId: _assistantRouteSourceId,
        lineColor: routeAssistantRouteColor.toARGB32(),
        lineWidth: 5.0,
        lineJoin: LineJoin.ROUND,
        lineCap: LineCap.ROUND,
      ),
    );
  }

  // Isolata in try/catch: se la registrazione delle icone fallisse a runtime,
  // non deve interrompere l'installazione degli altri layer (route, replay).
  Future<void> _installHabitualPlacesLayer() async {
    try {
      for (final marker in categoryMarkers) {
        final png = await renderCategoryIconPng(marker);
        await _map.style.addStyleImage(
          iconIdForCategory(marker.category),
          3.0,
          MbxImage(
            width: _categoryIconRenderSize,
            height: _categoryIconRenderSize,
            data: png,
          ),
          false,
          [],
          [],
          null,
        );
      }
      await _map.style.addSource(
        GeoJsonSource(
          id: _habitualPlacesSourceId,
          data: _labeledPointsGeoJson(const []),
        ),
      );
      await _map.style.addLayer(
        SymbolLayer(
          id: _habitualPlacesLabelLayerId,
          sourceId: _habitualPlacesSourceId,
          iconImageExpression: ['get', 'iconId'],
          iconAllowOverlap: true,
          textFieldExpression: ['get', 'label'],
          textSize: 12,
          textColor: _primaryColor,
          textHaloColor: _surfaceColor,
          textHaloWidth: 1.5,
          textAnchor: TextAnchor.TOP,
          textOffset: [0, 1.1],
          textAllowOverlap: true,
        ),
      );
      _habitualPlacesReady = true;
    } catch (_) {
      // Ignorato: il layer dei luoghi abituali e' opzionale.
    }
  }

  Future<void> _installReplayMarkerLayer() async {
    await _map.style.addSource(
      GeoJsonSource(id: _replayMarkerSourceId, data: _pointsGeoJson(const [])),
    );
    await _map.style.addLayer(
      CircleLayer(
        id: _replayMarkerHaloLayerId,
        sourceId: _replayMarkerSourceId,
        circleColor: _primaryColor,
        circleOpacity: 0.22,
        circleRadius: 18,
      ),
    );
    await _map.style.addLayer(
      CircleLayer(
        id: _replayMarkerDotLayerId,
        sourceId: _replayMarkerSourceId,
        circleColor: _primaryColor,
        circleRadius: 8,
        circleStrokeColor: _surfaceColor,
        circleStrokeWidth: 3,
      ),
    );
  }

  Future<void> redrawRoute(List<ll.LatLng> points) => _map.style
      .setStyleSourceProperty(_liveRouteSourceId, 'data', _lineGeoJson(points));

  Future<void> updateAssistantRoute(List<ll.LatLng> points) =>
      _map.style.setStyleSourceProperty(
        _assistantRouteSourceId,
        'data',
        _lineGeoJson(points),
      );

  Future<void> updateHabitualPlaces(List<LabeledPoint> places) {
    if (!_habitualPlacesReady) return Future.value();
    return _map.style.setStyleSourceProperty(
      _habitualPlacesSourceId,
      'data',
      _labeledPointsGeoJson(places),
    );
  }

  Future<void> updateReplayMarker({
    required bool isReplay,
    required ll.LatLng? latest,
  }) => _map.style.setStyleSourceProperty(
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

  static String _labeledPointsGeoJson(List<LabeledPoint> places) {
    return jsonEncode({
      'type': 'FeatureCollection',
      'features': [
        for (final place in places)
          {
            'type': 'Feature',
            'geometry': {
              'type': 'Point',
              'coordinates': [
                place.position.longitude,
                place.position.latitude,
              ],
            },
            'properties': {
              'label': place.label,
              'iconId': iconIdForCategory(place.category),
            },
          },
      ],
    });
  }
}
