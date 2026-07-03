part of 'dependency_injector.dart';

final List<BlocProvider> blocs = [
  BlocProvider<AuthCubit>(
    create: (context) => AuthCubit(
      context.read<AuthRepository>(),
    )..initialize(),
  ),
  BlocProvider<AcquisitionCubit>(
    create: (context) => AcquisitionCubit(
      context.read<AcquisitionRepository>(),
    ),
  ),
  BlocProvider<RouteAssistantCubit>(
    create: (context) => RouteAssistantCubit(
      context.read<RouteAssistantService>(),
      classifier: context.read<RouteClassifierService>(),
      locationProvider: currentDeviceLocation,
      activeLocationProvider: () {
        final acquisitionState = context.read<AcquisitionCubit>().state;
        return acquisitionState.isTracking
            ? acquisitionState.latestPosition
            : null;
      },
      sensorWindowProvider:
          context.read<AcquisitionRepository>().currentSensorWindow,
    ),
  ),
];
