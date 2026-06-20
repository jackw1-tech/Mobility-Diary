import 'package:auto_route/auto_route.dart';
import 'package:diary/network/service/trip_track_service.dart';
import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit.dart';
import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit_state.dart';
import 'package:diary/theme/color_palette.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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
        backgroundColor: ColorPalette.primary,
        foregroundColor: Colors.white,
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
  final MapController _controller = MapController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitTrack());
  }

  @override
  void didUpdateWidget(covariant _TrackMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.points != widget.state.points) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fitTrack());
    }
  }

  void _fitTrack() {
    if (!mounted || widget.state.points.isEmpty) return;
    final bounds = LatLngBounds.fromPoints(widget.state.points);
    _controller.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(40),
        maxZoom: 17,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.state.points;

    return Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            initialCenter: points.first,
            initialZoom: 14,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'diary',
            ),
            PolylineLayer(
              polylines: [
                Polyline(
                  points: points,
                  strokeWidth: 5,
                  color: ColorPalette.primary,
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                _marker(points.first, Icons.trip_origin, ColorPalette.success),
                _marker(points.last, Icons.flag, ColorPalette.error),
              ],
            ),
          ],
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

  Marker _marker(LatLng point, IconData icon, Color color) {
    return Marker(
      point: point,
      width: 40,
      height: 40,
      child: Icon(icon, color: color, size: 30),
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
        borderRadius: BorderRadius.circular(Dimensions.borderRadiusSmall),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
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
