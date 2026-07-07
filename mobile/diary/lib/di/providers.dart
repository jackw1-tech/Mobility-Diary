part of 'dependency_injector.dart';

List<SingleChildWidget> buildProviders({
  AuthSessionStore? authSessionStore,
}) =>
    [
      Provider<AuthSessionStore>(
        create: (_) => authSessionStore ?? const SecureAuthSessionStore(),
      ),
      Provider<TripTrackService>(
        create: (context) => TripTrackHttpService(
          tokenProvider: context.read<AuthSessionStore>().readAccessToken,
        ),
      ),
      Provider<TripsService>(
        create: (context) => TripsHttpService(
          tokenProvider: context.read<AuthSessionStore>().readAccessToken,
        ),
      ),
      Provider<TripIngestionService>(
        create: (context) => TripIngestionDioService(
          tokenProvider: context.read<AuthSessionStore>().readAccessToken,
        ),
      ),
      Provider<PlacesService>(
        create: (context) => PlacesHttpService(
          tokenProvider: context.read<AuthSessionStore>().readAccessToken,
        ),
      ),
      Provider<PrivacySettingsService>(
        create: (context) => PrivacySettingsHttpService(
          tokenProvider: context.read<AuthSessionStore>().readAccessToken,
        ),
      ),
      Provider<TripPrivacyExportService>(
        create: (context) => TripPrivacyExportHttpService(
          tokenProvider: context.read<AuthSessionStore>().readAccessToken,
        ),
      ),
      Provider<AnalyticsService>(
        create: (context) => AnalyticsHttpService(
          tokenProvider: context.read<AuthSessionStore>().readAccessToken,
        ),
      ),
      Provider<RouteAssistantService>(
        create: (_) => MapboxRouteAssistantService(),
      ),
      Provider<RouteClassifierService>(
        create: (context) => RouteClassifierHttpService(
          tokenProvider: context.read<AuthSessionStore>().readAccessToken,
        ),
      ),
    ];
