import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit_state.dart';
import 'package:diary/theme/color_palette.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:diary/ui/pages/trip_diary_presenter.dart';
import 'package:diary/ui/pages/trip_map_presenter.dart';
import 'package:diary/ui/widgets/trip_map/segment_details_sheet.dart';
import 'package:diary/ui/widgets/trip_map/trip_map_overlays.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Mappa Mapbox della traccia di un viaggio: disegna la polyline (intera o
/// spezzata per segmenti), i marker di partenza/arrivo e le soste riconosciute,
/// e apre il dettaglio toccando un segmento.
class TripTrackMap extends StatefulWidget {
  final TripTrackCubitState state;
  final Widget? topLeftOverlay;

  const TripTrackMap({
    required this.state,
    this.topLeftOverlay,
    super.key,
  });

  @override
  State<TripTrackMap> createState() => _TripTrackMapState();
}

class _TripTrackMapState extends State<TripTrackMap> {
  MapboxMap? _map;
  bool _styleReady = false;
  bool _showSegments = true;
  PolylineAnnotationManager? _lineManager;
  CircleAnnotationManager? _circleManager;
  final Map<String, TripTrackSegmentState> _segmentByAnnotationId = {};
  String? _selectedSegmentKey;

  @override
  void initState() {
    super.initState();
    _showSegments = widget.state.isSegmented;
  }

  @override
  void didUpdateWidget(covariant TripTrackMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final justSegmented =
        !oldWidget.state.isSegmented && widget.state.isSegmented;
    if (justSegmented) {
      // L'AI ha appena finito di segmentare il viaggio: passa alla vista
      // segmentata anche se l'utente stava guardando la traccia intera.
      _showSegments = true;
    }
    if (oldWidget.state.points != widget.state.points ||
        oldWidget.state.segments != widget.state.segments ||
        oldWidget.state.diarySegments != widget.state.diarySegments) {
      _drawTrack();
    }
  }

  Future<void> _onMapCreated(MapboxMap map) async {
    _map = map;
    await map.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
    await map.compass.updateSettings(CompassSettings(enabled: false));
    // Dentro una TabBarView vogliamo che i drag restino alla mappa e non
    // vengano interpretati come tentativi di cambio tab o gesture mancanti.
    await map.gestures.updateSettings(
      GesturesSettings(
        scrollEnabled: true,
        pinchToZoomEnabled: true,
        doubleTapToZoomInEnabled: true,
        doubleTouchToZoomOutEnabled: true,
        quickZoomEnabled: true,
        pitchEnabled: true,
        rotateEnabled: true,
      ),
    );
  }

  Future<void> _onStyleLoaded(StyleLoadedEventData _) async {
    _styleReady = true;
    await _drawTrack();
  }

  Future<void> _drawTrack() async {
    final map = _map;
    if (map == null || !_styleReady) return;
    final points = widget.state.points;
    if (points.isEmpty) return;

    final oldLineManager = _lineManager;
    final oldCircleManager = _circleManager;
    _lineManager = null;
    _circleManager = null;
    _segmentByAnnotationId.clear();
    _selectedSegmentKey = null;
    if (oldLineManager != null) {
      await map.annotations.removeAnnotationManager(oldLineManager);
    }
    if (oldCircleManager != null) {
      await map.annotations.removeAnnotationManager(oldCircleManager);
    }

    final lineManager = await map.annotations.createPolylineAnnotationManager();
    _lineManager = lineManager;
    if (_showSegments && widget.state.segments.isNotEmpty) {
      for (final segment in widget.state.segments) {
        final annotation = await _drawLine(
          lineManager,
          segment.points,
          activityColor(segment.activityLabel),
          isSelected: false,
        );
        if (annotation != null) {
          _segmentByAnnotationId[annotation.id] = segment;
        }
      }
      lineManager.tapEvents(onTap: _onSegmentTapped);
    } else {
      await _drawLine(
        lineManager,
        points,
        ColorPalette.primary,
        isSelected: false,
      );
    }

    final circleManager = await map.annotations.createCircleAnnotationManager();
    _circleManager = circleManager;
    await circleManager.create(
      CircleAnnotationOptions(
        geometry: Point(
          coordinates: Position(points.first.longitude, points.first.latitude),
        ),
        circleColor: ColorPalette.success.toARGB32(),
        circleRadius: 7,
        circleStrokeColor: Colors.white.toARGB32(),
        circleStrokeWidth: 2,
      ),
    );
    await circleManager.create(
      CircleAnnotationOptions(
        geometry: Point(
          coordinates: Position(points.last.longitude, points.last.latitude),
        ),
        circleColor: ColorPalette.error.toARGB32(),
        circleRadius: 7,
        circleStrokeColor: Colors.white.toARGB32(),
        circleStrokeWidth: 2,
      ),
    );
    for (final stop in placedStopSegments(widget.state.diarySegments)) {
      final place = stop.place!;
      await circleManager.create(
        CircleAnnotationOptions(
          geometry: Point(
            coordinates: Position(place.longitude, place.latitude),
          ),
          circleColor: Colors.black.toARGB32(),
          circleRadius: 6,
          circleStrokeColor: Colors.white.toARGB32(),
          circleStrokeWidth: 2,
        ),
      );
    }

    final currentCamera = await map.getCameraState();
    final bounds = await map.cameraForCoordinatesPadding(
      [
        for (final p in points)
          Point(coordinates: Position(p.longitude, p.latitude)),
      ],
      CameraOptions(bearing: currentCamera.bearing, pitch: currentCamera.pitch),
      MbxEdgeInsets(top: 60, left: 40, bottom: 60, right: 40),
      null,
      null,
    );
    await map.flyTo(bounds, MapAnimationOptions(duration: 600));
  }

  Future<PolylineAnnotation?> _drawLine(
      PolylineAnnotationManager lineManager, List<LatLng> points, Color color,
      {required bool isSelected}) async {
    if (points.length < 2) return null;
    return lineManager.create(
      PolylineAnnotationOptions(
        geometry: LineString(
          coordinates: [
            for (final p in points) Position(p.longitude, p.latitude),
          ],
        ),
        lineColor: color.toARGB32(),
        // Un tratto un po' piu' spesso rende il tap molto piu' affidabile su
        // mobile senza snaturare la leggibilita' della mappa.
        lineWidth: isSelected ? 12.0 : 9.0,
        lineOpacity: isSelected ? 1.0 : 0.82,
        lineJoin: LineJoin.ROUND,
      ),
    );
  }

  Future<void> _onSegmentTapped(PolylineAnnotation annotation) async {
    final segment = _segmentByAnnotationId[annotation.id];
    if (segment == null) return;
    await _highlightSelectedSegment(segmentKey(segment));
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SegmentDetailsSheet(
        color: activityColor(segment.activityLabel),
        activityLabel: activityLabelText(segment.activityLabel),
        distanceMeters: segment.distanceMeters,
        startTimestamp: segment.startTimestamp,
        endTimestamp: segment.endTimestamp,
      ),
    );
    await _highlightSelectedSegment(null);
  }

  Future<void> _highlightSelectedSegment(String? key) async {
    if (_selectedSegmentKey == key) return;
    if (!mounted) return;
    setState(() => _selectedSegmentKey = key);
    await _redrawSelectedSegments();
  }

  Future<void> _redrawSelectedSegments() async {
    final map = _map;
    final lineManager = _lineManager;
    if (map == null || lineManager == null || !_styleReady) return;
    if (!_showSegments || widget.state.segments.isEmpty) return;

    await lineManager.deleteAll();
    _segmentByAnnotationId.clear();

    for (final segment in widget.state.segments) {
      final color = activityColor(segment.activityLabel);
      final isSelected = _selectedSegmentKey != null &&
          _selectedSegmentKey == segmentKey(segment);
      final annotation = await _drawLine(
        lineManager,
        segment.points,
        color,
        isSelected: isSelected,
      );
      if (annotation != null) {
        _segmentByAnnotationId[annotation.id] = segment;
      }
    }
    lineManager.tapEvents(onTap: _onSegmentTapped);
  }

  void _toggleSegmented(bool showSegments) {
    if (_showSegments == showSegments) return;
    setState(() => _showSegments = showSegments);
    _drawTrack();
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.state.points;
    final hasEnrichmentBanner =
        widget.state.enrichmentPending || widget.state.enrichmentFailed;

    return Stack(
      children: [
        MapWidget(
          key: const ValueKey('trip-track-map'),
          styleUri: MapboxStyles.MAPBOX_STREETS,
          // ignore: deprecated_member_use
          cameraOptions: CameraOptions(
            center: Point(
              coordinates:
                  Position(points.first.longitude, points.first.latitude),
            ),
            zoom: 14,
          ),
          onMapCreated: _onMapCreated,
          onStyleLoadedListener: _onStyleLoaded,
        ),
        if (widget.state.enrichmentPending)
          const EnrichmentBanner(
            icon: Icons.auto_awesome,
            color: ColorPalette.info,
            message: 'Analisi diario in corso',
            showProgress: true,
          ),
        if (widget.state.enrichmentFailed)
          EnrichmentBanner(
            icon: Icons.error_outline,
            color: ColorPalette.error,
            message: widget.state.enrichmentErrorMessage ??
                'Diario non disponibile per questo viaggio.',
          ),
        if (widget.state.isSegmented)
          Positioned(
            top: hasEnrichmentBanner ? 96 : Dimensions.paddingMedium,
            right: Dimensions.paddingMedium,
            child: ViewModeToggle(
              showSegments: _showSegments,
              onChanged: _toggleSegmented,
            ),
          ),
        if (widget.topLeftOverlay != null)
          Positioned(
            top: hasEnrichmentBanner ? 96 : Dimensions.paddingMedium,
            left: Dimensions.paddingMedium,
            child: widget.topLeftOverlay!,
          ),
        Positioned(
          left: Dimensions.paddingMedium,
          right: Dimensions.paddingMedium,
          bottom: Dimensions.paddingMedium,
          child: DistanceOverlay(distanceMeters: widget.state.distanceMeters),
        ),
      ],
    );
  }
}
