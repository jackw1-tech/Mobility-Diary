import 'dart:convert';
import 'dart:math';

import 'package:diary/theme/semantic_colors.dart';
import 'package:diary/ui/pages/analytics_presenter.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class AnalyticsHeatmapMap extends StatefulWidget {
  final AnalyticsHeatmap heatmap;
  final bool interactive;
  final VoidCallback? onTap;

  const AnalyticsHeatmapMap({
    required this.heatmap,
    this.interactive = false,
    this.onTap,
    super.key,
  });

  @override
  State<AnalyticsHeatmapMap> createState() => _AnalyticsHeatmapMapState();
}

class _AnalyticsHeatmapMapState extends State<AnalyticsHeatmapMap> {
  static const _sourceId = 'analytics-heat-src';
  static const _layerId = 'analytics-heat-layer';
  static const _markerLayerId = 'analytics-place-marker-layer';
  MapboxMap? _map;

  Future<void> _onMapCreated(MapboxMap map) async {
    _map = map;
    await map.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
    await map.compass.updateSettings(CompassSettings(enabled: false));
    await map.gestures.updateSettings(
      GesturesSettings(
        scrollEnabled: widget.interactive,
        pinchToZoomEnabled: widget.interactive,
        rotateEnabled: widget.interactive,
        pitchEnabled: widget.interactive,
        doubleTapToZoomInEnabled: widget.interactive,
        doubleTouchToZoomOutEnabled: widget.interactive,
        quickZoomEnabled: widget.interactive,
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

    final primaryColor = Theme.of(context).colorScheme.primary.toARGB32();
    final surfaceColor = Theme.of(context).colorScheme.surface.toARGB32();

    await map.style.addSource(
      GeoJsonSource(
        id: _sourceId,
        data: jsonEncode({'type': 'FeatureCollection', 'features': features}),
      ),
    );
    if (points.length <= 3) {
      await map.style.addLayer(
        CircleLayer(
          id: _markerLayerId,
          sourceId: _sourceId,
          circleColor: primaryColor,
          circleOpacity: 0.82,
          circleRadiusExpression: [
            'interpolate',
            ['linear'],
            ['get', 'weight'],
            0,
            8.0,
            max(widget.heatmap.maxWeight, 1.0),
            18.0,
          ],
          circleStrokeColor: surfaceColor,
          circleStrokeWidth: 3,
        ),
      );
    } else {
      await map.style.addLayer(
        HeatmapLayer(
          id: _layerId,
          sourceId: _sourceId,
          heatmapRadius: 30,
          heatmapOpacity: 0.82,
          heatmapWeightExpression: [
            'interpolate',
            ['linear'],
            ['get', 'weight'],
            0,
            0.0,
            max(widget.heatmap.maxWeight, 1.0),
            1.0,
          ],
        ),
      );
    }

    if (points.length == 1) {
      final point = points.single;
      await map.setCamera(
        CameraOptions(
          center: Point(coordinates: Position(point.lon, point.lat)),
          zoom: 15,
        ),
      );
    } else {
      final camera = await map.cameraForCoordinatesPadding(
        [for (final p in points) Point(coordinates: Position(p.lon, p.lat))],
        CameraOptions(zoom: 13),
        MbxEdgeInsets(top: 48, left: 48, bottom: 48, right: 48),
        null,
        null,
      );
      await map.setCamera(camera);
    }
  }

  @override
  Widget build(BuildContext context) {
    final first = widget.heatmap.points.first;
    return Stack(
      children: [
        MapWidget(
          key: const ValueKey('analytics-heatmap'),
          styleUri: Theme.of(context).brightness == Brightness.dark
              ? MapboxStyles.DARK
              : MapboxStyles.MAPBOX_STREETS,
          // ignore: deprecated_member_use
          cameraOptions: CameraOptions(
            center: Point(coordinates: Position(first.lon, first.lat)),
            zoom: 14,
          ),
          onMapCreated: _onMapCreated,
          onStyleLoadedListener: _onStyleLoaded,
        ),
        Positioned(
          top: 12,
          left: 12,
          child: _HeatmapStats(heatmap: widget.heatmap),
        ),
        if (widget.onTap != null)
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(onTap: widget.onTap),
            ),
          ),
      ],
    );
  }
}

class AnalyticsHeatmapMapPage extends StatelessWidget {
  final String title;
  final AnalyticsHeatmap heatmap;

  const AnalyticsHeatmapMapPage({
    required this.title,
    required this.heatmap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: Text(title)),
      body: SafeArea(
        top: false,
        child: AnalyticsHeatmapMap(heatmap: heatmap, interactive: true),
      ),
    );
  }
}

class _HeatmapStats extends StatelessWidget {
  final AnalyticsHeatmap heatmap;

  const _HeatmapStats({required this.heatmap});

  @override
  Widget build(BuildContext context) {
    final places = heatmap.points.length;
    final visits = heatmap.points.fold<double>(
      0,
      (sum, point) => sum + point.weight,
    );
    final placeLabel = places == 1 ? '1 luogo' : '$places luoghi';
    final visitLabel = visits.round() == 1
        ? '1 visita'
        : '${visits.round()} visite';

    final sem = Theme.of(context).extension<SemanticColors>()!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: sem.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          '$placeLabel · $visitLabel',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
