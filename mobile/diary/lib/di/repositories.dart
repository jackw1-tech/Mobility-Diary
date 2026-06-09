part of 'dependency_injector.dart';

List<RepositoryProvider> buildRepositories({
  AuthRepository? authRepository,
}) =>
    [
      RepositoryProvider<AuthRepository>(
        create: (_) => authRepository ?? AuthRepositoryImpl(),
      ),
      RepositoryProvider<AcquisitionRepository>(
        create: (_) => AcquisitionRepositoryImpl(),
        dispose: (repository) => repository.dispose(),
      ),
    ];
