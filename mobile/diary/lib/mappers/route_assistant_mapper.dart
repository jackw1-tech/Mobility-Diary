import 'package:diary/model/entities/route_assistant/route_assistant_domain.dart';
import 'package:diary/network/dto/geocoding_feature_dto.dart';
import 'package:diary/network/dto/mapbox_route_dto.dart';
import 'package:latlong2/latlong.dart' as ll;

class RouteAssistantMapper {
  /// Converte le feature di geocoding grezze in luoghi di dominio, scartando
  /// le entry senza coordinate valide.
  List<GeocodingPlace> mapPlaces(List<GeocodingFeatureDto> dtos) {
    return dtos
        .map(_mapPlace)
        .whereType<GeocodingPlace>()
        .toList(growable: false);
  }

  GeocodingPlace? _mapPlace(GeocodingFeatureDto dto) {
    final location = _latLngFromCoordinate(dto.center);
    if (location == null) return null;
    return GeocodingPlace(label: dto.placeName ?? '', location: location);
  }

  /// Converte il primo percorso Mapbox valido in dominio. Lancia
  /// [RouteAssistantException] se non c'e' un percorso valido: e' una
  /// condizione di dominio ("nessun percorso trovato"), non un errore HTTP.
  RouteAssistantRoute mapRoute(MapboxRouteDto? dto) {
    if (dto == null) {
      throw const RouteAssistantException('Nessun percorso trovato');
    }
    final distance = dto.distanceMeters;
    final duration = dto.durationSeconds;
    if (distance == null || duration == null) {
      throw const RouteAssistantException('Dati percorso non validi');
    }
    final coordinates = dto.coordinates;
    if (coordinates == null) {
      throw const RouteAssistantException('Geometria percorso non valida');
    }
    final points = coordinates
        .map(_latLngFromCoordinate)
        .whereType<ll.LatLng>()
        .toList(growable: false);
    if (points.length < 2) {
      throw const RouteAssistantException('Geometria percorso non valida');
    }
    return RouteAssistantRoute(
      points: points,
      distanceMeters: distance.toDouble(),
      durationSeconds: duration.toDouble(),
    );
  }

  /// Converte l'etichetta grezza restituita dal classificatore live in
  /// [RouteMode]. Null per "idle" (fermo) o etichetta inattesa.
  RouteMode? mapClassificationLabel(String? label) {
    switch (label) {
      case 'walking':
        return RouteMode.walking;
      case 'cycling':
        return RouteMode.cycling;
      case 'driving':
        return RouteMode.driving;
      default:
        return null;
    }
  }

  ll.LatLng? _latLngFromCoordinate(dynamic coordinate) {
    if (coordinate is! List || coordinate.length < 2) return null;
    final lon = coordinate[0];
    final lat = coordinate[1];
    if (lon is! num || lat is! num) return null;
    return ll.LatLng(lat.toDouble(), lon.toDouble());
  }
}
