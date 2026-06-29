import 'dart:convert';
import 'dart:math';

import 'package:diary/ui/pages/analytics_presenter.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Mappa di Frequentazione: heatmap statica dei Luoghi Significativi pesati per
/// visite. La mappa e' non interattiva per non entrare in conflitto con lo
/// scroll della pagina; l'intensita' usa il peso normalizzato sul massimo.
class AnalyticsHeatmapMap extends StatefulWidget {
  final AnalyticsHeatmap heatmap;

  const AnalyticsHeatmapMap({required this.heatmap, super.key});

  @override
  State<AnalyticsHeatmapMap> createState() => _AnalyticsHeatmapMapState();
}

class _AnalyticsHeatmapMapState extends State<AnalyticsHeatmapMap> {
  static const _sourceId = 'analytics-heat-src';
  static const _layerId = 'analytics-heat-layer';
  MapboxMap? _map;

  Future<void> _onMapCreated(MapboxMap map) async {
    _map = map;
    await map.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
    await map.compass.updateSettings(CompassSettings(enabled: false));
    await map.gestures.updateSettings(
      GesturesSettings(
        scrollEnabled: false,
        pinchToZoomEnabled: false,
        rotateEnabled: false,
        pitchEnabled: false,
        doubleTapToZoomInEnabled: false,
        quickZoomEnabled: false,
      ),
    );
  }

  Future<void> _onStyleLoaded(StyleLoadedEventData _) async {
    final map = _map;
    final points = widget.heatmap.points;
    if (map == null || points.isEmpty) return;

    final features = [
      for (final point in points)
        {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [point.lon, point.lat],
          },
          'properties': {'weight': point.weight},
        },
    ];
    await map.style.addSource(GeoJsonSource(
      id: _sourceId,
      data: jsonEncode({'type': 'FeatureCollection', 'features': features}),
    ));
    await map.style.addLayer(HeatmapLayer(
      id: _layerId,
      sourceId: _sourceId,
      heatmapRadius: 26,
      heatmapOpacity: 0.85,
      heatmapWeightExpression: [
        'interpolate',
        ['linear'],
        ['get', 'weight'],
        0,
        0.0,
        max(widget.heatmap.maxWeight, 1.0),
        1.0,
      ],
    ));

    final camera = await map.cameraForCoordinatesPadding(
      [for (final p in points) Point(coordinates: Position(p.lon, p.lat))],
      CameraOptions(zoom: 12),
      MbxEdgeInsets(top: 40, left: 40, bottom: 40, right: 40),
      null,
      null,
    );
    await map.setCamera(camera);
  }

  @override
  Widget build(BuildContext context) {
    final first = widget.heatmap.points.first;
    return MapWidget(
      key: const ValueKey('analytics-heatmap'),
      styleUri: MapboxStyles.MAPBOX_STREETS,
      // ignore: deprecated_member_use
      cameraOptions: CameraOptions(
        center: Point(coordinates: Position(first.lon, first.lat)),
        zoom: 11,
      ),
      onMapCreated: _onMapCreated,
      onStyleLoadedListener: _onStyleLoaded,
    );
  }
}
