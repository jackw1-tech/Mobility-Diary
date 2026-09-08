import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit_state.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:diary/theme/semantic_colors.dart';
import 'package:diary/ui/pages/trip_diary_presenter.dart';
import 'package:diary/ui/pages/trip_map_presenter.dart';
import 'package:diary/ui/widgets/trip_map/segment_details_sheet.dart';
import 'package:diary/ui/widgets/trip_map/trip_map_overlays.dart';
import 'package:diary/utils/trip_detail_diagnostics.dart';
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
    _log(
      'map_widget_init_state',
      fields: {
        'point_count': widget.state.points.length,
        'segment_count': widget.state.segments.length,
        'diary_segment_count': widget.state.diarySegments.length,
      },
    );
  }

  @override
  void didUpdateWidget(covariant TripTrackMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final justSegmented =
        !oldWidget.state.isSegmented && widget.state.isSegmented;
    _log(
      'map_widget_updated',
      fields: {
        'points_changed': oldWidget.state.points != widget.state.points,
        'segments_changed': oldWidget.state.segments != widget.state.segments,
        'diary_changed':
            oldWidget.state.diarySegments != widget.state.diarySegments,
        'point_count': widget.state.points.length,
        'segment_count': widget.state.segments.length,
      },
    );
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
    final stopwatch = Stopwatch()..start();
    _log('mapbox_map_created');
    _map = map;
    await map.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
    _log(
      'mapbox_scale_bar_configured',
      fields: {'duration_ms': stopwatch.elapsedMilliseconds},
    );
    stopwatch.reset();
    await map.compass.updateSettings(CompassSettings(enabled: false));
    _log(
      'mapbox_compass_configured',
      fields: {'duration_ms': stopwatch.elapsedMilliseconds},
    );
    stopwatch.reset();
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
    _log(
      'mapbox_gestures_configured',
      fields: {'duration_ms': stopwatch.elapsedMilliseconds},
    );
  }

  Future<void> _onStyleLoaded(StyleLoadedEventData _) async {
    _log('mapbox_style_loaded');
    _styleReady = true;
    await _drawTrack();
  }

  bool _isStale(int drawId, String stage) {
    if (drawId == _drawSequence && mounted) return false;
    _log(
      'map_draw_abandoned',
      fields: {'draw_id': drawId, 'stage': stage, 'latest': _drawSequence},
    );
    return true;
  }

  Future<void> _drawTrack() async {
    final drawId = ++_drawSequence;
    final totalWatch = Stopwatch()..start();
    final map = _map;
    if (map == null || !_styleReady) {
      _log(
        'map_draw_skipped_not_ready',
        fields: {
          'draw_id': drawId,
          'has_map': map != null,
          'style_ready': _styleReady,
        },
      );
      return;
    }
    final points = widget.state.points;
    if (points.isEmpty) {
      _log('map_draw_skipped_empty', fields: {'draw_id': drawId});
      return;
    }

    _log(
      'map_draw_start',
      fields: {
        'draw_id': drawId,
        'point_count': points.length,
        'segment_count': widget.state.segments.length,
        'diary_segment_count': widget.state.diarySegments.length,
        'show_segments': _showSegments,
      },
    );

    try {
      var stageWatch = Stopwatch()..start();
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
      if (_isStale(drawId, 'old_annotations_removed')) return;
      _log(
        'map_old_annotations_removed',
        fields: {
          'draw_id': drawId,
          'duration_ms': stageWatch.elapsedMilliseconds,
          'had_line_manager': oldLineManager != null,
          'had_circle_manager': oldCircleManager != null,
        },
      );

      stageWatch = Stopwatch()..start();
      final lineManager =
          await map.annotations.createPolylineAnnotationManager();
      if (_isStale(drawId, 'line_manager_created')) {
        await map.annotations.removeAnnotationManager(lineManager);
        return;
      }
      _lineManager = lineManager;
      _log(
        'map_line_manager_created',
        fields: {
          'draw_id': drawId,
          'duration_ms': stageWatch.elapsedMilliseconds,
        },
      );
      if (!mounted) return;
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;
      final colorScheme = theme.colorScheme;
      final semantic =
          theme.extension<SemanticColors>() ?? SemanticColors.light;

      if (_showSegments && widget.state.segments.isNotEmpty) {
        final segments = widget.state.segments;
        final segmentWatch = Stopwatch()..start();
        var longestSegmentMs = 0;
        for (var index = 0; index < segments.length; index += 1) {
          final segment = segments[index];
          final singleWatch = Stopwatch()..start();
          final annotation = await _drawLine(
            lineManager,
            segment.points,
            activityColor(segment.activityLabel, colorScheme: colorScheme),
            isSelected: false,
          );
          if (_isStale(drawId, 'segment_draw')) return;
          final segmentMs = singleWatch.elapsedMilliseconds;
          if (segmentMs > longestSegmentMs) longestSegmentMs = segmentMs;
          if (annotation != null) {
            _segmentByAnnotationId[annotation.id] = segment;
          }
          final completed = index + 1;
          if (completed == 1 ||
              completed == segments.length ||
              completed % 25 == 0 ||
              segmentMs >= 100) {
            _log(
              'map_segment_draw_progress',
              fields: {
                'draw_id': drawId,
                'completed': completed,
                'total': segments.length,
                'segment_points': segment.points.length,
                'segment_ms': segmentMs,
                'cumulative_ms': segmentWatch.elapsedMilliseconds,
              },
            );
          }
        }
        lineManager.tapEvents(onTap: _onSegmentTapped);
        _log(
          'map_segments_draw_complete',
          fields: {
            'draw_id': drawId,
            'segment_count': segments.length,
            'duration_ms': segmentWatch.elapsedMilliseconds,
            'longest_segment_ms': longestSegmentMs,
          },
        );
      } else {
        stageWatch = Stopwatch()..start();
        await _drawLine(
          lineManager,
          points,
          colorScheme.primary,
          isSelected: false,
        );
        if (_isStale(drawId, 'raw_line_draw')) return;
        _log(
          'map_raw_line_draw_complete',
          fields: {
            'draw_id': drawId,
            'point_count': points.length,
            'duration_ms': stageWatch.elapsedMilliseconds,
          },
        );
      }

      stageWatch = Stopwatch()..start();
      final circleManager =
          await map.annotations.createCircleAnnotationManager();
      if (_isStale(drawId, 'circle_manager_created')) {
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
        await circleManager.create(
          CircleAnnotationOptions(
            geometry: Point(
              coordinates: Position(place.longitude, place.latitude),
            ),
            circleColor: colorScheme.primary.toARGB32(),
            circleRadius: 6,
            circleStrokeColor:
                (isDark ? Colors.black : Colors.white).toARGB32(),
            circleStrokeWidth: 2,
          ),
        );
      }
      _log(
        'map_markers_draw_complete',
        fields: {
          'draw_id': drawId,
          'stop_marker_count': stops.length,
          'duration_ms': stageWatch.elapsedMilliseconds,
        },
      );

      stageWatch = Stopwatch()..start();
      final currentCamera = await map.getCameraState();
      if (_isStale(drawId, 'camera_state')) return;
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
      _log(
        'map_camera_bounds_complete',
        fields: {
          'draw_id': drawId,
          'point_count': points.length,
          'duration_ms': stageWatch.elapsedMilliseconds,
        },
      );

      if (_isStale(drawId, 'camera_bounds')) return;
      stageWatch = Stopwatch()..start();
      await map.flyTo(bounds, MapAnimationOptions(duration: 600));
      _log(
        'map_camera_fly_complete',
        fields: {
          'draw_id': drawId,
          'duration_ms': stageWatch.elapsedMilliseconds,
        },
      );
      _log(
        'map_draw_complete',
        fields: {
          'draw_id': drawId,
          'total_duration_ms': totalWatch.elapsedMilliseconds,
        },
      );
    } catch (error) {
      _log(
        'map_draw_error',
        fields: {
          'draw_id': drawId,
          'total_duration_ms': totalWatch.elapsedMilliseconds,
          'error_type': error.runtimeType,
        },
      );
      rethrow;
    }
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

  void _log(
    String stage, {
    Map<String, Object?> fields = const {},
  }) {
    TripDetailDiagnostics.event(
      widget.state.diagnosticsTraceId,
      stage,
      fields: fields,
    );
  }

  @override
  void dispose() {
    _log('map_widget_disposed');
    super.dispose();
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
