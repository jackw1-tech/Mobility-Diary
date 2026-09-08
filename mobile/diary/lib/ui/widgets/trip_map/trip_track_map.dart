import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit_state.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:diary/theme/semantic_colors.dart';
import 'package:diary/ui/pages/trip_diary_presenter.dart';
import 'package:diary/ui/pages/trip_map_presenter.dart';
import 'package:diary/ui/widgets/trip_map/segment_details_sheet.dart';
import 'package:diary/ui/widgets/trip_map/trip_map_overlays.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Mappa Mapbox della traccia di un viaggio in trip detail page
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
  int _drawSequence = 0;

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
    // Quando cambia il widget perchè il diary ha finito il caricamento -> riemetto ripTrackStatus.loaded ma lo era già quindi viene eseguita didUpdateWidget
    if (justSegmented) {
      _showSegments = true;
    }
    //Facco scattare l'effettivo ridisegno solo se points, segments o diarySegments sono diversi (quando l har ha finito quindi -> dal diary)
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

  bool _isStale(int drawId) {
    if (drawId == _drawSequence && mounted) return false;
    return true;
  }

  Future<void> _drawTrack() async {
    final drawId = ++_drawSequence;
    final map = _map;
    if (map == null || !_styleReady) {
      return;
    }
    final points = widget.state.points;
    if (points.isEmpty) {
      return;
    }

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
      if (_isStale(drawId)) return;

      final lineManager =
          await map.annotations.createPolylineAnnotationManager();
      if (_isStale(drawId)) {
        await map.annotations.removeAnnotationManager(lineManager);
        return;
      }
      _lineManager = lineManager;
      if (!mounted) return;
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;
      final colorScheme = theme.colorScheme;
      final semantic =
          theme.extension<SemanticColors>() ?? SemanticColors.light;

      if (_showSegments && widget.state.segments.isNotEmpty) {
        final segments = widget.state.segments;
        for (var index = 0; index < segments.length; index += 1) {
          final segment = segments[index];
          final annotation = await _drawLine(
            lineManager,
            segment.points,
            activityColor(segment.activityLabel, colorScheme: colorScheme),
            isSelected: false,
          );
          if (_isStale(drawId)) return;
          if (annotation != null) {
            _segmentByAnnotationId[annotation.id] = segment;
          }
        }
        lineManager.tapEvents(onTap: _onSegmentTapped);
      } else {
        await _drawLine(
          lineManager,
          points,
          colorScheme.primary,
          isSelected: false,
        );
        if (_isStale(drawId)) return;
      }

      final circleManager =
          await map.annotations.createCircleAnnotationManager();
      if (_isStale(drawId)) {
        await map.annotations.removeAnnotationManager(circleManager);
        return;
      }
      _circleManager = circleManager;
      await circleManager.create(
        CircleAnnotationOptions(
          geometry: Point(
            coordinates:
                Position(points.first.longitude, points.first.latitude),
          ),
          circleColor: semantic.success.toARGB32(),
          circleRadius: 7,
          circleStrokeColor: (isDark ? Colors.black : Colors.white).toARGB32(),
          circleStrokeWidth: 2,
        ),
      );
      await circleManager.create(
        CircleAnnotationOptions(
          geometry: Point(
            coordinates: Position(points.last.longitude, points.last.latitude),
          ),
          circleColor: semantic.error.toARGB32(),
          circleRadius: 7,
          circleStrokeColor: (isDark ? Colors.black : Colors.white).toARGB32(),
          circleStrokeWidth: 2,
        ),
      );
      final stops = placedStopSegments(widget.state.diarySegments);
      for (final stop in stops) {
        final place = stop.place!;
        final stopGeometry = Point(
          coordinates: Position(place.longitude, place.latitude),
        );
        await circleManager.create(
          CircleAnnotationOptions(
            geometry: stopGeometry,
            circleColor: colorScheme.primary.toARGB32(),
            circleRadius: 30,
            circleOpacity: 0.18,
          ),
        );
        await circleManager.create(
          CircleAnnotationOptions(
            geometry: stopGeometry,
            circleColor: colorScheme.primary.toARGB32(),
            circleRadius: 6,
            circleStrokeColor:
                (isDark ? Colors.black : Colors.white).toARGB32(),
            circleStrokeWidth: 2,
          ),
        );
      }

      final currentCamera = await map.getCameraState();
      if (_isStale(drawId)) return;
      final bounds = await map.cameraForCoordinatesPadding(
        [
          for (final p in points)
            Point(coordinates: Position(p.longitude, p.latitude)),
        ],
        CameraOptions(
          bearing: currentCamera.bearing,
          pitch: currentCamera.pitch,
        ),
        MbxEdgeInsets(top: 60, left: 40, bottom: 60, right: 40),
        null,
        null,
      );

    if (_isStale(drawId)) return;
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
    final colorScheme = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SegmentDetailsSheet(
        color: activityColor(segment.activityLabel, colorScheme: colorScheme),
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

    if (!mounted) return;
    final colorScheme = Theme.of(context).colorScheme;
    for (final segment in widget.state.segments) {
      final color =
          activityColor(segment.activityLabel, colorScheme: colorScheme);
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
    final hasProcessingBanner =
        widget.state.processingPending || widget.state.processingFailed;
    final theme = Theme.of(context);

    return Stack(
      children: [
        MapWidget(
          key: const ValueKey('trip-track-map'),
          styleUri: theme.brightness == Brightness.dark
              ? MapboxStyles.DARK
              : MapboxStyles.MAPBOX_STREETS,
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
        if (widget.state.processingPending)
          ProcessingBanner(
            icon: Icons.auto_awesome,
            color: theme.colorScheme.primary,
            message: 'Analisi diario in corso',
            showProgress: true,
          ),
        if (widget.state.processingFailed)
          ProcessingBanner(
            icon: Icons.error_outline,
            color: theme.colorScheme.error,
            message: widget.state.processingErrorMessage ??
                'Diario non disponibile per questo viaggio.',
          ),
        if (widget.state.isSegmented)
          Positioned(
            top: hasProcessingBanner ? 96 : Dimensions.paddingMedium,
            right: Dimensions.paddingMedium,
            child: ViewModeToggle(
              showSegments: _showSegments,
              onChanged: _toggleSegmented,
            ),
          ),
        if (widget.topLeftOverlay != null)
          Positioned(
            top: hasProcessingBanner ? 96 : Dimensions.paddingMedium,
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
