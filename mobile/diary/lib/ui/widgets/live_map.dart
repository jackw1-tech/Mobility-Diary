import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit_state.dart';
import 'package:diary/state_management/cubits/current_location_cubit/current_location_cubit.dart';
import 'package:diary/theme/color_palette.dart';
import 'package:diary/ui/widgets/live_map_camera_controller.dart';
import 'package:diary/ui/widgets/live_map_layers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit.dart';
import 'package:diary/state_management/cubits/route_assistant_cubit/route_assistant_cubit.dart';
import 'package:diary/state_management/cubits/route_assistant_cubit/route_assistant_cubit_state.dart';
import 'package:diary/ui/widgets/route_assistant_controls.dart';

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
  MapboxMap? _map;
  LiveMapLayers? _layers;
  LiveMapCameraController? _camera;
  Point? _initialCenter;
  String? _error;
  RouteAssistantCubit? _routeAssistantCubit;

  /// Se true la camera insegue automaticamente la posizione corrente.
  bool _followUser = true;

  @override
  void initState() {
    super.initState();
    _resolveInitialCenter();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncPassiveModeDetection();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeAssistantCubit = context.read<RouteAssistantCubit>();
  }

  @override
  void dispose() {
    _routeAssistantCubit?.setPassiveModeDetectionEnabled(false);
    super.dispose();
  }

  Future<void> _resolveInitialCenter() async {
    // La UI non parla mai direttamente col LocationRepository: la posizione
    // arriva dal CurrentLocationCubit, come vuole il flusso Pine UI -> Cubit
    // -> Repository.
    final cubit = context.read<CurrentLocationCubit>();
    final location = await cubit.resolve();
    if (!mounted) return;
    final error = cubit.state.error;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _initialCenter = location == null
          ? Point(coordinates: Position(0, 0))
          : Point(
              coordinates: Position(location.longitude, location.latitude),
            );
    });
  }

  Future<void> _onMapCreated(MapboxMap map) async {
    _map = map;
    _camera = LiveMapCameraController(map);
    // Niente bussola/scale ridondanti: la UI ha già i suoi overlay.
    await map.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
    await map.compass.updateSettings(CompassSettings(enabled: false));
    // Puck nativo: pallino + alone di accuratezza + freccia di direzione.
    await _camera!.syncNativePuck(isReplay: false);
  }

  Future<void> _onStyleLoaded(StyleLoadedEventData _) async {
    final map = _map;
    if (map == null) return;
    final cubit = context.read<AcquisitionCubit>();
    final assistant = context.read<RouteAssistantCubit>();
    final layers = await LiveMapLayers.install(map);
    _layers = layers;
    await layers.redrawRoute(cubit.state.routePoints);
    await _camera?.syncNativePuck(isReplay: cubit.state.isReplay);
    await layers.updateReplayMarker(
      isReplay: cubit.state.isReplay,
      latest: cubit.state.latestPosition,
    );
    await layers.updateAssistantRoute(assistant.state.routePoints);
  }

  Future<void> _followTo(ll.LatLng target) async {
    if (!_followUser) return;
    await _camera?.flyTo(target);
  }

  void _pauseFollowForGesture(MapContentGestureContext context) {
    if (!_followUser || context.gestureState == GestureState.ended) return;
    setState(() => _followUser = false);
  }

  // Ogni volta che il repository emette uno snapshot con nuovi punti GPS,
  // aggiorna la polyline
  void _onStateChanged(AcquisitionCubitState state) {
    _layers?.redrawRoute(state.routePoints);
    _camera?.syncNativePuck(isReplay: state.isReplay);
    _layers?.updateReplayMarker(
      isReplay: state.isReplay,
      latest: state.latestPosition,
    );
    _syncPassiveModeDetection();
    final latest = state.latestPosition;
    if (latest != null && state.isTracking) {
      _followTo(latest);
    }
  }

  void _syncPassiveModeDetection() {
    final acquisitionState = context.read<AcquisitionCubit>().state;
    final assistant = context.read<RouteAssistantCubit>();
    if (!acquisitionState.isTracking) {
      assistant.clearDetectedModePrediction();
    }
    assistant.setPassiveModeDetectionEnabled(
      acquisitionState.isTracking && !assistant.state.isActive,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _MapMessage(message: _error!);
    }
    if (_initialCenter == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return MultiBlocListener(
      listeners: [
        BlocListener<AcquisitionCubit, AcquisitionCubitState>(
          listenWhen: (previous, current) =>
              previous.routePoints != current.routePoints ||
              previous.latestPosition != current.latestPosition ||
              previous.isTracking != current.isTracking ||
              previous.isReplay != current.isReplay,
          listener: (context, state) => _onStateChanged(state),
        ),
        BlocListener<RouteAssistantCubit, RouteAssistantState>(
          listenWhen: (previous, current) =>
              previous.routePoints != current.routePoints,
          listener: (context, state) {
            _layers?.updateAssistantRoute(state.routePoints);
            _syncPassiveModeDetection();
          },
        ),
      ],
      child: Stack(
        children: [
          MapWidget(
            key: const ValueKey('live-map'),
            styleUri: MapboxStyles.MAPBOX_STREETS,
            // ignore: deprecated_member_use
            cameraOptions: CameraOptions(
              center: _initialCenter,
              zoom: LiveMapCameraController.followZoom,
            ),
            onMapCreated: _onMapCreated,
            onStyleLoadedListener: _onStyleLoaded,
            onScrollListener: _pauseFollowForGesture,
            onZoomListener: _pauseFollowForGesture,
          ),
          BlocBuilder<AcquisitionCubit, AcquisitionCubitState>(
            buildWhen: (previous, current) =>
                previous.isTracking != current.isTracking,
            builder: (context, acquisitionState) =>
                BlocBuilder<RouteAssistantCubit, RouteAssistantState>(
              buildWhen: (previous, current) =>
                  previous.isActive != current.isActive ||
                  previous.detectedMode != current.detectedMode ||
                  previous.hasDetectedModeResult !=
                      current.hasDetectedModeResult,
              builder: (context, assistantState) {
                if (!acquisitionState.isTracking || assistantState.isActive) {
                  return const SizedBox.shrink();
                }
                return RouteDetectedModeIndicator(
                  mode: assistantState.detectedMode,
                  hasResult: assistantState.hasDetectedModeResult,
                );
              },
            ),
          ),
          BlocBuilder<AcquisitionCubit, AcquisitionCubitState>(
            buildWhen: (previous, current) =>
                previous.isTracking != current.isTracking,
            builder: (context, state) =>
                RouteAssistantControls(liveEnabled: state.isTracking),
          ),
          Positioned(
            right: 0,
            top: 2,
            child: _RecenterButton(
              active: _followUser,
              onPressed: () async {
                setState(() => _followUser = true);
                final latest =
                    context.read<AcquisitionCubit>().state.latestPosition;
                if (latest != null) {
                  await _followTo(latest);
                } else {
                  final location =
                      await context.read<CurrentLocationCubit>().resolve();
                  if (location != null) {
                    await _followTo(location);
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
