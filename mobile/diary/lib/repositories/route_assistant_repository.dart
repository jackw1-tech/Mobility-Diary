import 'package:diary/utils/app_result.dart';
import 'package:diary/model/entities/route_assistant/route_assistant_domain.dart';
import 'package:latlong2/latlong.dart' as ll;

abstract class RouteAssistantRepository {
  Future<AppResult<List<GeocodingPlace>>> searchPlaces(
    String query, {
    ll.LatLng? proximity,
  });

  Future<AppResult<RouteAssistantRoute>> fetchRoute({
    required ll.LatLng from,
    required ll.LatLng to,
    required RouteMode mode,
  });

  Future<AppResult<RouteMode?>> classify(List<List<double>> samples);
}
