import 'package:diary/utils/app_result.dart';
import 'package:diary/mappers/route_assistant_mapper.dart';
import 'package:diary/model/entities/route_assistant/route_assistant_domain.dart';
import 'package:diary/network/service/route_assistant_service.dart';
import 'package:diary/network/service/route_classifier_service.dart';
import 'package:diary/repositories/route_assistant_repository.dart';
import 'package:latlong2/latlong.dart' as ll;

class RouteAssistantRepositoryImpl implements RouteAssistantRepository {
  final RouteAssistantService _service;
  final RouteClassifierService _classifier;
  final RouteAssistantMapper _mapper;

  const RouteAssistantRepositoryImpl({
    required RouteAssistantService service,
    required RouteClassifierService classifier,
    required RouteAssistantMapper mapper,
  })  : _service = service,
        _classifier = classifier,
        _mapper = mapper;

  @override
  Future<AppResult<List<GeocodingPlace>>> searchPlaces(
    String query, {
    ll.LatLng? proximity,
  }) =>
      appResultOf(
        () async => _mapper.mapPlaces(
          await _service.searchPlaces(query, proximity: proximity),
        ),
      );

  @override
  Future<AppResult<RouteAssistantRoute>> fetchRoute({
    required ll.LatLng from,
    required ll.LatLng to,
    required RouteMode mode,
  }) =>
      appResultOf(
        () async => _mapper.mapRoute(
          await _service.fetchRoute(from: from, to: to, mode: mode),
        ),
      );

  @override
  Future<AppResult<RouteMode?>> classify(List<List<double>> samples) =>
      appResultOf(
        () async =>
            _mapper.mapClassificationLabel(await _classifier.classify(samples)),
      );
}
