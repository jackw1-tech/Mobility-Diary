part of 'dependency_injector.dart';

List<RepositoryProvider> buildRepositories({
  AuthRepository? authRepository,
}) =>
    [
      RepositoryProvider<AuthRepository>(
        create: (_) => authRepository ?? AuthRepositoryImpl(),
      ),
      RepositoryProvider<TripTrackService>(
        create: (context) {
          final auth = context.read<AuthRepository>();
          return TripTrackHttpService(
            tokenProvider: () async => auth.accessToken,
          );
        },
      ),
      RepositoryProvider<TripsService>(
        create: (context) {
          final auth = context.read<AuthRepository>();
          return TripsHttpService(
            tokenProvider: () async => auth.accessToken,
          );
        },
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
          final ingestionApi =
              TripIngestionHttpApi(tokenProvider: tokenProvider);
          final syncQueue = TripSyncQueueImpl(
            dao: database.acquisitionDao,
            builder: TripPackageBuilder(dao: database.acquisitionDao),
            api: ingestionApi,
            tokenProvider: tokenProvider,
            tripsService: context.read<TripsService>(),
          );
          return AcquisitionRepositoryImpl(
            database: database,
            syncQueue: syncQueue,
            ingestionApi: ingestionApi,
            deviceIdProvider: deviceIdentityStore.getOrCreateDeviceId,
            observeAppLifecycle: true,
          );
        },
        dispose: (repository) => repository.dispose(),
      ),
      RepositoryProvider<PlacesService>(
        create: (context) {
          final auth = context.read<AuthRepository>();
          return PlacesHttpService(
            tokenProvider: () async => auth.accessToken,
          );
        },
      ),
      RepositoryProvider<PrivacySettingsService>(
        create: (context) {
          final auth = context.read<AuthRepository>();
          return PrivacySettingsHttpService(
            tokenProvider: () async => auth.accessToken,
          );
        },
      ),
      RepositoryProvider<TripPrivacyExportService>(
        create: (context) {
          final auth = context.read<AuthRepository>();
          return TripPrivacyExportHttpService(
            tokenProvider: () async => auth.accessToken,
          );
        },
      ),
      RepositoryProvider<AnalyticsService>(
        create: (context) {
          final auth = context.read<AuthRepository>();
          return AnalyticsHttpService(
            tokenProvider: () async => auth.accessToken,
          );
        },
      ),
      RepositoryProvider<RouteAssistantService>(
        create: (_) => MapboxRouteAssistantService(),
      ),
      RepositoryProvider<RouteClassifierService>(
        create: (context) {
          final auth = context.read<AuthRepository>();
          return RouteClassifierHttpService(
            tokenProvider: () async => auth.accessToken,
          );
        },
      ),
    ];

/// Posizione GPS corrente (punto A dell'assistente di percorso). Indipendente
/// dall'AcquisitionCubit: usa direttamente il geolocator.
Future<ll.LatLng?> currentDeviceLocation() async {
  if (!await geo.Geolocator.isLocationServiceEnabled()) return null;
  var permission = await geo.Geolocator.checkPermission();
  if (permission == geo.LocationPermission.denied) {
    permission = await geo.Geolocator.requestPermission();
  }
  if (permission == geo.LocationPermission.denied ||
      permission == geo.LocationPermission.deniedForever) {
    return null;
  }
  final position = await geo.Geolocator.getLastKnownPosition() ??
      await geo.Geolocator.getCurrentPosition();
  return ll.LatLng(position.latitude, position.longitude);
}
