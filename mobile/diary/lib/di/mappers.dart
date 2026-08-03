part of 'dependency_injector.dart';

final List<SingleChildWidget> _mappers = [
  Provider<AuthMapper>(
    create: (_) => AuthMapper(),
  ),
  Provider<IngestionMapper>(
    create: (_) => IngestionMapper(),
  ),
  Provider<TripsMapper>(
    create: (_) => TripsMapper(),
  ),
  Provider<AnalyticsMapper>(
    create: (_) => AnalyticsMapper(),
  ),
  Provider<PlacesMapper>(
    create: (_) => PlacesMapper(),
  ),
  Provider<TripPrivacyExportMapper>(
    create: (_) => TripPrivacyExportMapper(),
  ),
  Provider<PrivacySettingsMapper>(
    create: (_) => PrivacySettingsMapper(),
  ),
  Provider<RouteAssistantMapper>(
    create: (_) => RouteAssistantMapper(),
  ),
];
