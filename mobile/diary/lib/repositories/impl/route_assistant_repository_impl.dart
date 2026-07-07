import 'package:diary/features/common/domain/app_result.dart';
import 'package:diary/features/route_assistant/domain/route_assistant_domain.dart';
import 'package:diary/network/service/route_assistant_service.dart';
import 'package:diary/network/service/route_classifier_service.dart';
import 'package:diary/repositories/route_assistant_repository.dart';
import 'package:latlong2/latlong.dart' as ll;

class RouteAssistantRepositoryImpl implements RouteAssistantRepository {
  final RouteAssistantService _service;
  final RouteClassifierService _classifier;

  const RouteAssistantRepositoryImpl({
    required RouteAssistantService service,
    required RouteClassifierService classifier,
  })  : _service = service,
        _classifier = classifier;

  @override
  Future<AppResult<List<GeocodingPlace>>> searchPlaces(
    String query, {
    ll.LatLng? proximity,
  }) =>
      appResultOf(
        () => _service.searchPlaces(query, proximity: proximity),
      );

  @override
  Future<AppResult<RouteAssistantRoute>> fetchRoute({
    required ll.LatLng from,
    required ll.LatLng to,
    required RouteMode mode,
  }) =>
      appResultOf(
        () => _service.fetchRoute(from: from, to: to, mode: mode),
      );

  @override
  Future<AppResult<RouteMode?>> classify(List<List<double>> samples) =>
      appResultOf(() => _classifier.classify(samples));
}
