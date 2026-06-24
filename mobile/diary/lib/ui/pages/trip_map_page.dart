import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit.dart';
import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit_state.dart';
import 'package:diary/theme/color_palette.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:diary/ui/pages/trip_diary_presenter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class TripMapPage extends StatelessWidget {
  const TripMapPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TripTrackCubit, TripTrackCubitState>(
      builder: (context, state) {
        switch (state.status) {
          case TripTrackStatus.initial:
          case TripTrackStatus.loading:
            return const Center(child: CircularProgressIndicator());
          case TripTrackStatus.loaded:
            return _TrackMap(state: state);
          case TripTrackStatus.empty:
            return const _EmptyTrack();
          case TripTrackStatus.error:
            return _TrackError(
              message: state.error ?? 'Errore sconosciuto',
              onRetry: () => context.read<TripTrackCubit>().reload(),
            );
        }
      },
    );
  }
}

class _TrackMap extends StatefulWidget {
  final TripTrackCubitState state;

  const _TrackMap({required this.state});

  @override
  State<_TrackMap> createState() => _TrackMapState();
}

class _TrackMapState extends State<_TrackMap> {
  MapboxMap? _map;
  bool _styleReady = false;
  bool _showSegments = true;
  PolylineAnnotationManager? _lineManager;
  CircleAnnotationManager? _circleManager;
  final Map<String, TripTrackSegmentState> _segmentByAnnotationId = {};

  @override
  void initState() {
    super.initState();
    _showSegments = widget.state.isSegmented;
  }

  @override
  void didUpdateWidget(covariant _TrackMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final justSegmented =
        !oldWidget.state.isSegmented && widget.state.isSegmented;
    if (justSegmented) {
      // L'AI ha appena finito di segmentare il viaggio: passa alla vista
      // segmentata anche se l'utente stava guardando la traccia intera.
      _showSegments = true;
    }
    if (oldWidget.state.points != widget.state.points ||
        oldWidget.state.segments != widget.state.segments) {
      _drawTrack();
    }
  }

  Future<void> _onMapCreated(MapboxMap map) async {
    _map = map;
    await map.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
    await map.compass.updateSettings(CompassSettings(enabled: false));
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
          _activityColor(segment.activityLabel),
        );
        if (annotation != null) {
          _segmentByAnnotationId[annotation.id] = segment;
        }
      }
      lineManager.tapEvents(onTap: _onSegmentTapped);
    } else {
      await _drawLine(lineManager, points, ColorPalette.primary);
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
    PolylineAnnotationManager lineManager,
    List<LatLng> points,
    Color color,
  ) async {
    if (points.length < 2) return null;
    return lineManager.create(
      PolylineAnnotationOptions(
        geometry: LineString(
          coordinates: [
            for (final p in points) Position(p.longitude, p.latitude),
          ],
        ),
        lineColor: color.toARGB32(),
        lineWidth: 5.0,
        lineJoin: LineJoin.ROUND,
      ),
    );
  }

  Color _activityColor(String label) {
    switch (label) {
      case 'WALKING':
        return const Color(0xFF1F8A4C);
      case 'RUNNING':
        return const Color(0xFFE04F5F);
      case 'BIKING':
        return const Color(0xFF2563EB);
      case 'MOVING_VEHICLE':
        return const Color(0xFF6D5DF6);
      default:
        return ColorPalette.primary;
    }
  }

  void _onSegmentTapped(PolylineAnnotation annotation) {
    final segment = _segmentByAnnotationId[annotation.id];
    if (segment == null) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _SegmentDetailsSheet(
        color: _activityColor(segment.activityLabel),
        activityLabel: activityLabelText(segment.activityLabel),
        distanceMeters: segment.distanceMeters,
      ),
    );
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
          const _EnrichmentBanner(
            icon: Icons.auto_awesome,
            color: ColorPalette.info,
            message: 'Analisi diario in corso',
            showProgress: true,
          ),
        if (widget.state.enrichmentFailed)
          _EnrichmentBanner(
            icon: Icons.error_outline,
            color: ColorPalette.error,
            message: widget.state.enrichmentErrorMessage ??
                'Diario non disponibile per questo viaggio.',
          ),
        if (widget.state.isSegmented)
          Positioned(
            top: hasEnrichmentBanner ? 96 : Dimensions.paddingMedium,
            right: Dimensions.paddingMedium,
            child: _ViewModeToggle(
              showSegments: _showSegments,
              onChanged: _toggleSegmented,
            ),
          ),
        Positioned(
          left: Dimensions.paddingMedium,
          right: Dimensions.paddingMedium,
          bottom: Dimensions.paddingMedium,
          child: _DistanceOverlay(distanceMeters: widget.state.distanceMeters),
        ),
      ],
    );
  }
}

class _EnrichmentBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;
  final bool showProgress;

  const _EnrichmentBanner({
    required this.icon,
    required this.color,
    required this.message,
    this.showProgress = false,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: Dimensions.paddingMedium,
      top: Dimensions.paddingMedium,
      right: Dimensions.paddingMedium,
      child: Material(
        color: ColorPalette.surface,
        elevation: Dimensions.cardElevation,
        borderRadius: BorderRadius.circular(Dimensions.borderRadiusMedium),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Dimensions.borderRadiusMedium),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showProgress) const LinearProgressIndicator(minHeight: 3),
              Padding(
                padding: const EdgeInsets.all(Dimensions.paddingSmall),
                child: Row(
                  children: [
                    Icon(icon, color: color, size: 18),
                    const SizedBox(width: Dimensions.paddingSmall),
                    Expanded(
                      child: Text(
                        message,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ViewModeToggle extends StatelessWidget {
  final bool showSegments;
  final ValueChanged<bool> onChanged;

  const _ViewModeToggle({
    required this.showSegments,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ColorPalette.surface,
      elevation: Dimensions.cardElevation,
      borderRadius: BorderRadius.circular(Dimensions.borderRadiusLarge),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              icon: Icon(Icons.timeline),
              label: Text('Traccia'),
            ),
            ButtonSegment(
              value: true,
              icon: Icon(Icons.route),
              label: Text('Segmenti'),
            ),
          ],
          selected: {showSegments},
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
      ),
    );
  }
}

class _SegmentDetailsSheet extends StatelessWidget {
  final Color color;
  final String activityLabel;
  final double distanceMeters;

  const _SegmentDetailsSheet({
    required this.color,
    required this.activityLabel,
    required this.distanceMeters,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Dimensions.paddingLarge,
        Dimensions.paddingSmall,
        Dimensions.paddingLarge,
        Dimensions.paddingLarge,
      ),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: Dimensions.paddingMedium),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activityLabel,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                Text(
                  formatDistance(distanceMeters),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: ColorPalette.textSecondary,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DistanceOverlay extends StatelessWidget {
  final double distanceMeters;

  const _DistanceOverlay({required this.distanceMeters});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Dimensions.borderRadiusLarge),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(Dimensions.paddingMedium),
        child: Row(
          children: [
            const Icon(Icons.route, color: ColorPalette.primary),
            const SizedBox(width: Dimensions.paddingSmall),
            Text(
              formatDistance(distanceMeters),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyTrack extends StatelessWidget {
  const _EmptyTrack();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(Dimensions.paddingLarge),
        child: Text('Traiettoria non disponibile'),
      ),
    );
  }
}

class _TrackError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _TrackError({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Dimensions.paddingLarge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: ColorPalette.error),
            const SizedBox(height: Dimensions.paddingSmall),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: Dimensions.paddingMedium),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Riprova'),
            ),
          ],
        ),
      ),
    );
  }
}
