part of 'dependency_injector.dart';

final List<SingleChildWidget> _mappers = [
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
];
