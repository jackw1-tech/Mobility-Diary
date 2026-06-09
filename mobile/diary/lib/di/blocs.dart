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
];
