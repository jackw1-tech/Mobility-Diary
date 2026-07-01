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
      sensorWindowProvider:
          context.read<AcquisitionRepository>().currentSensorWindow,
    ),
  ),
];
