import 'package:auto_route/auto_route.dart';
import 'package:diary/network/service/trip_track_service.dart';
import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit.dart';
import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit_state.dart';
import 'package:diary/theme/color_palette.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

@RoutePage()
class TripMapPage extends StatelessWidget {
  final int tripId;

  const TripMapPage({
    @PathParam('id') required this.tripId,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          TripTrackCubit(context.read<TripTrackService>())..load(tripId),
      child: _TripMapView(tripId: tripId),
    );
  }
}

class _TripMapView extends StatelessWidget {
  final int tripId;

  const _TripMapView({required this.tripId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Traiettoria'),
        actions: [
          IconButton(
            tooltip: 'Ricarica',
            onPressed: () => context.read<TripTrackCubit>().load(tripId),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: BlocBuilder<TripTrackCubit, TripTrackCubitState>(
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
                onRetry: () => context.read<TripTrackCubit>().load(tripId),
              );
          }
        },
      ),
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

  @override
  void didUpdateWidget(covariant _TrackMap oldWidget) {
    super.didUpdateWidget(oldWidget);
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

    final lineManager = await map.annotations.createPolylineAnnotationManager();
    if (widget.state.segments.isNotEmpty) {
      for (final segment in widget.state.segments) {
        await _drawLine(
          lineManager,
          segment.points,
          _activityColor(segment.activityLabel),
        );
      }
    } else {
      await _drawLine(lineManager, points, ColorPalette.primary);
    }

    final circleManager = await map.annotations.createCircleAnnotationManager();
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

  Future<void> _drawLine(
    PolylineAnnotationManager lineManager,
    List<LatLng> points,
    Color color,
  ) async {
    if (points.length < 2) return;
    await lineManager.create(
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

  @override
  Widget build(BuildContext context) {
    final points = widget.state.points;

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
          const Positioned(
            left: 0,
            top: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 3),
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
              _formatDistance(distanceMeters),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(2)} km';
    }
    return '${meters.round()} m';
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
