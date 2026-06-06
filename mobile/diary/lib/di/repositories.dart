part of 'dependency_injector.dart';

final List<RepositoryProvider> repositories = [
  RepositoryProvider<AcquisitionRepository>(
    create: (_) => AcquisitionRepositoryImpl(),
    dispose: (repository) => repository.dispose(),
  ),
];
