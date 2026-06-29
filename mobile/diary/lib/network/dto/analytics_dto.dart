/// Analitiche Personali: bucket finestrati (tempo per Categoria di Mobilita) +
/// aggregati cumulativi (modalita' prevalente, Percorsi Frequenti, heatmap).
/// Generata backend-side (ADR 0030); l'app la mappa e la disegna soltanto.
class AnalyticsDto {
  final String granularity;
  final bool hasData;
  final List<AnalyticsBucketDto> buckets;
  final String? prevalentMode;
  final List<AnalyticsRouteDto> frequentRoutes;
  final List<AnalyticsHeatPointDto> heatmap;

  const AnalyticsDto({
    required this.granularity,
    required this.hasData,
    required this.buckets,
    required this.prevalentMode,
    required this.frequentRoutes,
    required this.heatmap,
  });

  factory AnalyticsDto.fromJson(Map<String, dynamic> json) {
    return AnalyticsDto(
      granularity: json['granularity'] as String? ?? 'day',
      hasData: json['has_data'] as bool? ?? false,
      buckets: _list(json['buckets'], AnalyticsBucketDto.fromJson),
      prevalentMode: json['prevalent_mode'] as String?,
      frequentRoutes: _list(json['frequent_routes'], AnalyticsRouteDto.fromJson),
      heatmap: _list(json['heatmap'], AnalyticsHeatPointDto.fromJson),
    );
  }
}

class AnalyticsBucketDto {
  final String label;
  final List<AnalyticsCategorySliceDto> categories;

  const AnalyticsBucketDto({required this.label, required this.categories});

  factory AnalyticsBucketDto.fromJson(Map<String, dynamic> json) {
    return AnalyticsBucketDto(
      label: json['label'] as String? ?? '',
      categories:
          _list(json['categories'], AnalyticsCategorySliceDto.fromJson),
    );
  }
}

class AnalyticsCategorySliceDto {
  final String category;
  final double seconds;
  final double distanceMeters;

  const AnalyticsCategorySliceDto({
    required this.category,
    required this.seconds,
    required this.distanceMeters,
  });

  factory AnalyticsCategorySliceDto.fromJson(Map<String, dynamic> json) {
    return AnalyticsCategorySliceDto(
      category: json['category'] as String? ?? '',
      seconds: (json['seconds'] as num? ?? 0).toDouble(),
      distanceMeters: (json['distance_meters'] as num? ?? 0).toDouble(),
    );
  }
}

class AnalyticsRouteDto {
  final String originLabel;
  final String destinationLabel;
  final int tripCount;

  const AnalyticsRouteDto({
    required this.originLabel,
    required this.destinationLabel,
    required this.tripCount,
  });

  factory AnalyticsRouteDto.fromJson(Map<String, dynamic> json) {
    return AnalyticsRouteDto(
      originLabel: json['origin_label'] as String? ?? '',
      destinationLabel: json['destination_label'] as String? ?? '',
      tripCount: json['trip_count'] as int? ?? 0,
    );
  }
}

class AnalyticsHeatPointDto {
  final double lat;
  final double lon;
  final double weight;

  const AnalyticsHeatPointDto({
    required this.lat,
    required this.lon,
    required this.weight,
  });

  factory AnalyticsHeatPointDto.fromJson(Map<String, dynamic> json) {
    return AnalyticsHeatPointDto(
      lat: (json['lat'] as num? ?? 0).toDouble(),
      lon: (json['lon'] as num? ?? 0).toDouble(),
      weight: (json['weight'] as num? ?? 0).toDouble(),
    );
  }
}

List<T> _list<T>(
  dynamic value,
  T Function(Map<String, dynamic>) fromJson,
) {
  return (value as List<dynamic>? ?? const [])
      .map((item) => fromJson(Map<String, dynamic>.from(item as Map)))
      .toList(growable: false);
}
