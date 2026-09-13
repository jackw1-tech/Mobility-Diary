import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit_state.dart';
import 'package:diary/state_management/cubits/current_location_cubit/current_location_cubit.dart';
import 'package:diary/state_management/cubits/places_cubit/places_cubit.dart';
import 'package:diary/state_management/cubits/places_cubit/places_cubit_state.dart';
import 'package:diary/repositories/places_repository.dart';

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
  PlacesCubit? _placesCubit;

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
    _placesCubit ??= PlacesCubit(context.read<PlacesRepository>())..load();
  }

  @override
  void dispose() {
    _routeAssistantCubit?.setPassiveModeDetectionEnabled(false);
    _placesCubit?.close();
    super.dispose();
  }

  Future<void> _resolveInitialCenter() async {
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
          : Point(coordinates: Position(location.longitude, location.latitude));
    });
  }

  Future<void> _onMapCreated(MapboxMap map) async {
    _map = map;
    _camera = LiveMapCameraController(map);
    await map.scaleBar.updateSettings(ScaleBarSettings(enabled: false));
    await map.compass.updateSettings(CompassSettings(enabled: false));
    await _camera!.syncNativePuck(isReplay: false);
  }

  Future<void> _onStyleLoaded(StyleLoadedEventData _) async {
    final map = _map;
    if (map == null) return;
    final cubit = context.read<AcquisitionCubit>();
    final assistant = context.read<RouteAssistantCubit>();
    final colorScheme = Theme.of(context).colorScheme;
    final layers = await LiveMapLayers.install(
      map,
      primary: colorScheme.primary,
      surface: colorScheme.surface,
    );
    _layers = layers;
    await layers.redrawRoute(cubit.state.routePoints);
    await _camera?.syncNativePuck(isReplay: cubit.state.isReplay);
    await layers.updateReplayMarker(
      isReplay: cubit.state.isReplay,
      latest: cubit.state.latestPosition,
    );
    await layers.updateAssistantRoute(assistant.state.routePoints);
    await _syncHabitualPlaces(isTracking: cubit.state.isTracking);
  }

  Future<void> _syncHabitualPlaces({required bool isTracking}) async {
    if (isTracking) {
      await _layers?.updateHabitualPlaces(const []);
      return;
    }
    final confirmed = _placesCubit?.state.confirmed ?? const [];
    await _layers?.updateHabitualPlaces([
      for (final place in confirmed)
        LabeledPoint(
          position: place.center,
          label: place.label,
          category: place.category,
        ),
    ]);
  }

  Future<void> _followTo(ll.LatLng target) async {
    if (!_followUser) return;
    await _camera?.flyTo(target);
  }

  void _pauseFollowForGesture(MapContentGestureContext context) {
    if (!_followUser || context.gestureState == GestureState.ended) return;
    setState(() => _followUser = false);
  }

  void _onStateChanged(AcquisitionCubitState state) {
    _layers?.redrawRoute(state.routePoints);
    _camera?.syncNativePuck(isReplay: state.isReplay);
    _layers?.updateReplayMarker(
      isReplay: state.isReplay,
      latest: state.latestPosition,
    );
    _syncHabitualPlaces(isTracking: state.isTracking);
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

    return BlocProvider<PlacesCubit>.value(
      value: _placesCubit!,
      child: MultiBlocListener(
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
          BlocListener<PlacesCubit, PlacesCubitState>(
            listenWhen: (previous, current) =>
                previous.places != current.places,
            listener: (context, state) => _syncHabitualPlaces(
              isTracking: context.read<AcquisitionCubit>().state.isTracking,
            ),
          ),
        ],
        child: Stack(
          children: [
            MapWidget(
              key: const ValueKey('live-map'),
              styleUri: Theme.of(context).brightness == Brightness.dark
                  ? MapboxStyles.DARK
                  : MapboxStyles.MAPBOX_STREETS,
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
                            current.hasDetectedModeResult ||
                        previous.classificationTick !=
                            current.classificationTick,
                    builder: (context, assistantState) {
                      if (!acquisitionState.isTracking ||
                          assistantState.isActive) {
                        return const SizedBox.shrink();
                      }
                      return RouteDetectedModeIndicator(
                        mode: assistantState.detectedMode,
                        hasResult: assistantState.hasDetectedModeResult,
                        classificationTick: assistantState.classificationTick,
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
                  final latest = context
                      .read<AcquisitionCubit>()
                      .state
                      .latestPosition;
                  if (latest != null) {
                    await _followTo(latest);
                  } else {
                    final location = await context
                        .read<CurrentLocationCubit>()
                        .resolve();
                    if (location != null) {
                      await _followTo(location);
                    }
                  }
                },
              ),
            ),
          ],
        ),
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
    final colorScheme = Theme.of(context).colorScheme;
    return FloatingActionButton.small(
      heroTag: 'live-map-recenter',
      backgroundColor: colorScheme.surface,
      foregroundColor: active
          ? colorScheme.primary
          : colorScheme.onSurfaceVariant,
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
