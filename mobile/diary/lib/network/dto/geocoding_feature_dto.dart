/// DTO grezzo (shape wire) di una singola feature della risposta di
/// geocoding Mapbox (`/geocoding/v5/mapbox.places`). Consumato solo da
/// [RouteAssistantMapper].
class GeocodingFeatureDto {
  final String? placeName;

  /// Coordinata grezza `[lon, lat]` cosi' come restituita da Mapbox (`center`).
  final List<dynamic>? center;

  const GeocodingFeatureDto({this.placeName, this.center});

  factory GeocodingFeatureDto.fromJson(Map<String, dynamic> json) {
    return GeocodingFeatureDto(
      placeName: json['place_name'] as String?,
      center: json['center'] as List<dynamic>?,
    );
  }
}
