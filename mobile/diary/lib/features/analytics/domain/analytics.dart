class Analytics {
  final String granularity;
  final bool hasData;
  final List<AnalyticsBucket> buckets;
  final String? prevalentMode;
  final List<AnalyticsRoute> frequentRoutes;
  final List<AnalyticsHeatPoint> heatmap;
  final List<AnalyticsWeeklyHeatmap> weeklyHeatmaps;

  const Analytics({
    required this.granularity,
    required this.hasData,
    required this.buckets,
    required this.prevalentMode,
    required this.frequentRoutes,
    required this.heatmap,
    this.weeklyHeatmaps = const [],
  });
}

class AnalyticsBucket {
  final String label;
  final List<AnalyticsCategorySlice> categories;

  const AnalyticsBucket({required this.label, required this.categories});
}

class AnalyticsCategorySlice {
  final String category;
  final double seconds;
  final double distanceMeters;

  const AnalyticsCategorySlice({
    required this.category,
    required this.seconds,
    required this.distanceMeters,
  });
}

class AnalyticsRoute {
  final String originLabel;
  final String destinationLabel;
  final int tripCount;

  const AnalyticsRoute({
    required this.originLabel,
    required this.destinationLabel,
    required this.tripCount,
  });
}

class AnalyticsHeatPoint {
  final double lat;
  final double lon;
  final double weight;

  const AnalyticsHeatPoint({
    required this.lat,
    required this.lon,
    required this.weight,
  });
}

class AnalyticsWeeklyHeatmap {
  final String label;
  final List<int> tripIds;
  final List<AnalyticsHeatPoint> habitualPlaces;

  const AnalyticsWeeklyHeatmap({
    required this.label,
    required this.tripIds,
    required this.habitualPlaces,
  });
}
