part of 'dependency_injector.dart';

List<RepositoryProvider> buildRepositories({
  AuthRepository? authRepository,
}) =>
    [
      RepositoryProvider<AuthRepository>(
        create: (context) =>
            authRepository ??
            AuthRepositoryImpl(
              service: context.read<AuthService>(),
              mapper: context.read<AuthMapper>(),
              sessionStore: context.read<AuthSessionStore>(),
            ),
      ),
      RepositoryProvider<LocationRepository>(
        create: (_) => const GeolocatorLocationRepository(),
      ),
      RepositoryProvider<AcquisitionRepository>(
        create: (context) {
          final database = context.read<AcquisitionLocalDatabase>();
          final auth = context.read<AuthRepository>();
          Future<String?> tokenProvider() async => auth.accessToken;
          final deviceIdentityStore = context.read<DeviceIdentityStore>();
          final uploadService = context.read<TripUploadService>();
          final mapper = context.read<UploadMapper>();
          final acquisitionMapper = context.read<AcquisitionMapper>();
          final syncQueue = TripSyncQueueImpl(
            dao: database.acquisitionDao,
            builder: TripPackageBuilder(
              dao: database.acquisitionDao,
              acquisitionMapper: acquisitionMapper,
              uploadMapper: mapper,
            ),
            service: uploadService,
            mapper: mapper,
            tokenProvider: tokenProvider,
            tripsService: context.read<TripsService>(),
          );
          return AcquisitionRepositoryImpl(
            database: database,
            syncKick: syncQueue.kick,
            uploadService: uploadService,
            mapper: mapper,
            acquisitionMapper: context.read<AcquisitionMapper>(),
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
          mapper: context.read<PrivacySettingsMapper>(),
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
          mapper: context.read<RouteAssistantMapper>(),
        ),
      ),
    ];
