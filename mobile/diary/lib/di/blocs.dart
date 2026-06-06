part of 'dependency_injector.dart';

final List<BlocProvider> blocs = [
  BlocProvider<AcquisitionCubit>(
    create: (context) => AcquisitionCubit(
      context.read<AcquisitionRepository>(),
    ),
  ),
];
