part of 'dependency_injector.dart';

final List<BlocProvider> blocs = [
  BlocProvider<AuthCubit>(
    create: (context) => AuthCubit(
      context.read<AuthRepository>(),
    )..initialize(),
  ),
  BlocProvider<AcquisitionCubit>(
    create: (context) => AcquisitionCubit(
      trackingRepository: context.read<AcquisitionTrackingRepository>(),
      syncRepository: context.read<AcquisitionSyncRepository>(),
    ),
  ),
  BlocProvider<CurrentLocationCubit>(
    create: (context) => CurrentLocationCubit(
      context.read<LocationRepository>(),
    ),
  ),
  BlocProvider<RouteAssistantCubit>(
    create: (context) => RouteAssistantCubit(
      context.read<RouteAssistantRepository>(),
      locationProvider: context.read<LocationRepository>().currentLocation,
      activeLocationProvider: () {
        final acquisitionState = context.read<AcquisitionCubit>().state;
        return acquisitionState.isTracking
            ? acquisitionState.latestPosition
            : null;
      },
      sensorWindowProvider:
          context.read<AcquisitionTrackingRepository>().currentSensorWindow,
    ),
  ),
];
