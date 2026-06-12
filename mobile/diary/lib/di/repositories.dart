part of 'dependency_injector.dart';

List<RepositoryProvider> buildRepositories({
  AuthRepository? authRepository,
}) =>
    [
      RepositoryProvider<AuthRepository>(
        create: (_) => authRepository ?? AuthRepositoryImpl(),
      ),
      RepositoryProvider<AcquisitionRepository>(
        create: (context) {
          final database = AcquisitionLocalDatabase();
          final auth = context.read<AuthRepository>();
          Future<String?> tokenProvider() async => auth.accessToken;
          final syncQueue = TripSyncQueueImpl(
            dao: database.acquisitionDao,
            builder: TripPackageBuilder(dao: database.acquisitionDao),
            api: TripIngestionHttpApi(tokenProvider: tokenProvider),
            tokenProvider: tokenProvider,
          );
          return AcquisitionRepositoryImpl(
            database: database,
            syncQueue: syncQueue,
          );
        },
        dispose: (repository) => repository.dispose(),
      ),
    ];
