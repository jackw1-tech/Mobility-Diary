import 'package:diary/model/entities/analytics/analytics.dart';
import 'package:diary/network/dto/analytics_dto.dart';

class AnalyticsMapper {
  Analytics mapAnalytics(AnalyticsDto dto) => Analytics(
        granularity: dto.granularity,
        hasData: dto.hasData,
        buckets: dto.buckets.map(mapBucket).toList(growable: false),
        prevalentMode: dto.prevalentMode,
        frequentRoutes:
            dto.frequentRoutes.map(mapRoute).toList(growable: false),
        heatmap: dto.heatmap.map(mapHeatPoint).toList(growable: false),
        weeklyHeatmaps:
            dto.weeklyHeatmaps.map(mapWeeklyHeatmap).toList(growable: false),
      );

  AnalyticsBucket mapBucket(AnalyticsBucketDto dto) => AnalyticsBucket(
        label: dto.label,
        categories: dto.categories.map(mapSlice).toList(growable: false),
      );

  AnalyticsCategorySlice mapSlice(AnalyticsCategorySliceDto dto) {
    return AnalyticsCategorySlice(
      category: dto.category,
      seconds: dto.seconds,
      distanceMeters: dto.distanceMeters,
    );
  }

  AnalyticsRoute mapRoute(AnalyticsRouteDto dto) => AnalyticsRoute(
        originLabel: dto.originLabel,
        destinationLabel: dto.destinationLabel,
        tripCount: dto.tripCount,
      );

  AnalyticsHeatPoint mapHeatPoint(AnalyticsHeatPointDto dto) =>
      AnalyticsHeatPoint(
        lat: dto.lat,
        lon: dto.lon,
        weight: dto.weight,
      );

  AnalyticsWeeklyHeatmap mapWeeklyHeatmap(AnalyticsWeeklyHeatmapDto dto) {
    return AnalyticsWeeklyHeatmap(
      label: dto.label,
      tripIds: dto.tripIds,
      habitualPlaces:
          dto.habitualPlaces.map(mapHeatPoint).toList(growable: false),
    );
  }
}
