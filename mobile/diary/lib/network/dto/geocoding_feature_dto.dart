class GeocodingFeatureDto {
  final String? placeName;

  final List<dynamic>? center;

  const GeocodingFeatureDto({this.placeName, this.center});

  factory GeocodingFeatureDto.fromJson(Map<String, dynamic> json) {
    return GeocodingFeatureDto(
      placeName: json['place_name'] as String?,
      center: json['center'] as List<dynamic>?,
    );
  }
}
