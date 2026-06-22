import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit_state.dart';
import 'package:diary/theme/color_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:latlong2/latlong.dart' as ll;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit.dart';

/// Mappa live a tutto schermo:
///  - mostra subito il "puck" della posizione corrente (Location Component
///    nativo di Mapbox), che si muove in modo fluido a ogni fix GPS;
///  - durante il tracking disegna la polyline del percorso leggendo
///    `routePoints` dall'[AcquisitionCubit].
class LiveMap extends StatefulWidget {
  const LiveMap({super.key});

  @override
  State<LiveMap> createState() => _LiveMapState();
}

class _LiveMapState extends State<LiveMap> {
  static const double _followZoom = 16.5;

  MapboxMap? _map;
  PolylineAnnotationManager? _routeManager;
  Point? _initialCenter;
  String? _error;
  bool _styleReady = false;

  /// Se true la camera insegue automaticamente la posizione corrente.
  bool _followUser = true;

  @override
  void initState() {
    super.initState();
    _resolveInitialCenter();
  }

  Future<void> _resolveInitialCenter() async {
    try {
      final position = await _currentPositionOrNull();
      if (!mounted) return;
      setState(() {
        _initialCenter = position == null
            ? Point(coordinates: Position(0, 0))
            : Point(
                coordinates: Position(position.longitude, position.latitude),
              );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Posizione non disponibile: $e');
    }
  }

  Future<geo.Position?> _currentPositionOrNull() async {
    final serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    var permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }
    if (permission == geo.LocationPermission.denied ||
        permission == geo.LocationPermission.deniedForever) {
      return null;
    }

    final last = await geo.Geolocator.getLastKnownPosition();
    if (last != null) return last;
    return geo.Geolocator.getCurrentPosition();
  }

  Future<void> _onMapCreated(MapboxMap map) async {
    _map = map;
    // Niente bussola/scale ridondanti: la UI ha già i suoi overlay.
    await map.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
    await map.compass.updateSettings(CompassSettings(enabled: false));
    // Puck nativo: pallino + alone di accuratezza + freccia di direzione.
    await map.location.updateSettings(
      LocationComponentSettings(
        enabled: true,
        pulsingEnabled: true,
        showAccuracyRing: true,
        puckBearingEnabled: true,
        puckBearing: PuckBearing.HEADING,
      ),
    );
  }

  Future<void> _onStyleLoaded(StyleLoadedEventData _) async {
    final map = _map;
    if (map == null) return;
    // Catturato prima dell'await per non usare context oltre l'async gap.
    final cubit = context.read<AcquisitionCubit>();
    _routeManager = await map.annotations.createPolylineAnnotationManager();
    _styleReady = true;
    // Se entriamo con una sessione già in corso, ridisegna subito.
    await _redrawRoute(cubit.state.routePoints);
  }

  Future<void> _redrawRoute(List<ll.LatLng> points) async {
    final manager = _routeManager;
    if (manager == null || !_styleReady) return;

    await manager.deleteAll();
    if (points.length < 2) return;

    await manager.create(
      PolylineAnnotationOptions(
        geometry: LineString(
          coordinates: [
            for (final p in points) Position(p.longitude, p.latitude),
          ],
        ),
        lineColor: ColorPalette.primary.toARGB32(),
        lineWidth: 5.0,
        lineJoin: LineJoin.ROUND,
      ),
    );
  }

  Future<void> _followTo(ll.LatLng target) async {
    if (!_followUser) return;
    await _map?.flyTo(
      CameraOptions(
        center: Point(coordinates: Position(target.longitude, target.latitude)),
        zoom: _followZoom,
      ),
      MapAnimationOptions(duration: 900),
    );
  }

  void _onStateChanged(AcquisitionCubitState state) {
    _redrawRoute(state.routePoints);
    final latest = state.latestPosition;
    if (latest != null && state.isTracking) {
      _followTo(latest);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _MapMessage(message: _error!);
    }
    if (_initialCenter == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return BlocListener<AcquisitionCubit, AcquisitionCubitState>(
      listenWhen: (previous, current) =>
          previous.routePoints != current.routePoints ||
          previous.latestPosition != current.latestPosition ||
          previous.isTracking != current.isTracking,
      listener: (context, state) => _onStateChanged(state),
      child: Stack(
        children: [
          MapWidget(
            key: const ValueKey('live-map'),
            styleUri: MapboxStyles.MAPBOX_STREETS,
            // ignore: deprecated_member_use
            cameraOptions: CameraOptions(
              center: _initialCenter,
              zoom: _followZoom,
            ),
            onMapCreated: _onMapCreated,
            onStyleLoadedListener: _onStyleLoaded,
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: _RecenterButton(
              active: _followUser,
              onPressed: () async {
                setState(() => _followUser = true);
                final latest =
                    context.read<AcquisitionCubit>().state.latestPosition;
                if (latest != null) {
                  await _followTo(latest);
                } else {
                  final pos = await _currentPositionOrNull();
                  if (pos != null) {
                    await _followTo(ll.LatLng(pos.latitude, pos.longitude));
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RecenterButton extends StatelessWidget {
  final bool active;
  final VoidCallback onPressed;

  const _RecenterButton({required this.active, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      heroTag: 'live-map-recenter',
      backgroundColor: Colors.white,
      foregroundColor:
          active ? ColorPalette.primary : ColorPalette.textSecondary,
      onPressed: onPressed,
      child: const Icon(Icons.my_location),
    );
  }
}

class _MapMessage extends StatelessWidget {
  final String message;

  const _MapMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
