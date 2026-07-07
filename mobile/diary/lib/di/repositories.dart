part of 'dependency_injector.dart';

List<RepositoryProvider> buildRepositories({
  AuthRepository? authRepository,
}) =>
    [
      RepositoryProvider<AuthRepository>(
        create: (context) =>
            authRepository ??
            AuthRepositoryImpl(
              sessionStore: context.read<AuthSessionStore>(),
            ),
      ),
      RepositoryProvider<LocationRepository>(
        create: (_) => const GeolocatorLocationRepository(),
      ),
      // Deve stare dopo TripsService: la coda di sync la usa per eliminare
      // anche il Trip lato backend (se il core era gia' andato a buon fine)
      // quando scarta in automatico un viaggio la cui sync e' fallita in modo
      // definitivo, non solo il residuo locale.
      RepositoryProvider<AcquisitionRepository>(
        create: (context) {
          final database = AcquisitionLocalDatabase();
          final auth = context.read<AuthRepository>();
          Future<String?> tokenProvider() async => auth.accessToken;
          final deviceIdentityStore = DeviceIdentityStore();
          final ingestionService = context.read<TripIngestionService>();
          final mapper = context.read<IngestionMapper>();
          final syncQueue = TripSyncQueueImpl(
            dao: database.acquisitionDao,
            builder: TripPackageBuilder(dao: database.acquisitionDao),
            service: ingestionService,
            mapper: mapper,
            tokenProvider: tokenProvider,
            tripsService: context.read<TripsService>(),
          );
          return AcquisitionRepositoryImpl(
            database: database,
            syncQueue: syncQueue,
            ingestionService: ingestionService,
            mapper: mapper,
            deviceIdProvider: deviceIdentityStore.getOrCreateDeviceId,
            observeAppLifecycle: true,
          );
        },
        dispose: (repository) => repository.dispose(),
      ),
      RepositoryProvider<AcquisitionTrackingRepository>(
        create: (context) => context.read<AcquisitionRepository>(),
      ),
      RepositoryProvider<AcquisitionSyncRepository>(
        create: (context) => context.read<AcquisitionRepository>(),
      ),
      RepositoryProvider<AcquisitionLocalTripPurger>(
        create: (context) => context.read<AcquisitionRepository>(),
      ),
      RepositoryProvider<TripsRepository>(
        create: (context) => TripsRepositoryImpl(
          service: context.read<TripsService>(),
          mapper: context.read<TripsMapper>(),
          localTripPurger: context.read<AcquisitionLocalTripPurger>(),
        ),
      ),
      RepositoryProvider<TripTrackRepository>(
        create: (context) => TripTrackRepositoryImpl(
          service: context.read<TripTrackService>(),
          mapper: context.read<TripsMapper>(),
        ),
      ),
      RepositoryProvider<AnalyticsRepository>(
        create: (context) => AnalyticsRepositoryImpl(
          service: context.read<AnalyticsService>(),
          mapper: context.read<AnalyticsMapper>(),
        ),
      ),
      RepositoryProvider<PlacesRepository>(
        create: (context) => PlacesRepositoryImpl(
          service: context.read<PlacesService>(),
          mapper: context.read<PlacesMapper>(),
        ),
      ),
      RepositoryProvider<PrivacySettingsRepository>(
        create: (context) => PrivacySettingsRepositoryImpl(
          service: context.read<PrivacySettingsService>(),
        ),
      ),
      RepositoryProvider<TripPrivacyExportRepository>(
        create: (context) => TripPrivacyExportRepositoryImpl(
          service: context.read<TripPrivacyExportService>(),
          mapper: context.read<TripPrivacyExportMapper>(),
        ),
      ),
      RepositoryProvider<RouteAssistantRepository>(
        create: (context) => RouteAssistantRepositoryImpl(
          service: context.read<RouteAssistantService>(),
          classifier: context.read<RouteClassifierService>(),
        ),
      ),
    ];
