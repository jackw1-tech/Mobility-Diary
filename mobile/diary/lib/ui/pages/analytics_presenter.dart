import 'package:diary/model/entities/analytics/analytics.dart';
import 'package:flutter/material.dart';

class MobilityCategory {
  final String key;
  final String label;
  final Color color;
  const MobilityCategory(this.key, this.label, this.color);
}

const kMobilityCategories = <MobilityCategory>[
  MobilityCategory('fermo', 'Fermo', Color(0xFF8C8C8C)),
  MobilityCategory('a_piedi', 'A piedi', Color(0xFF1F8A70)),
  MobilityCategory('corsa', 'Corsa', Color(0xFFC43D3D)),
  MobilityCategory('in_bici', 'In bici', Color(0xFF2563EB)),
  MobilityCategory('in_auto', 'In auto', Color(0xFF8A5CF6)),
];

class AnalyticsBar {
  final String label;
  final List<double> secondsByCategory;
  const AnalyticsBar(this.label, this.secondsByCategory);
}

class AnalyticsCategoryTotal {
  final MobilityCategory category;
  final Duration time;
  final double distanceMeters;
  const AnalyticsCategoryTotal(this.category, this.time, this.distanceMeters);
}

class AnalyticsTotals {
  final Duration movementTime;
  final double totalDistanceMeters;
  final List<AnalyticsCategoryTotal> categoryTotals;

  const AnalyticsTotals({
    required this.movementTime,
    required this.totalDistanceMeters,
    required this.categoryTotals,
  });
}

const kAnalyticsWindowSize = 7;

MobilityCategory? categoryByKey(String? key) {
  for (final category in kMobilityCategories) {
    if (category.key == key) return category;
  }
  return null;
}

class AnalyticsHabits {
  final MobilityCategory? prevalentMode;
  final List<AnalyticsRoute> routes;
  const AnalyticsHabits(this.prevalentMode, this.routes);

  bool get isEmpty => prevalentMode == null && routes.isEmpty;
}

AnalyticsHabits buildAnalyticsHabits(Analytics data) =>
    AnalyticsHabits(categoryByKey(data.prevalentMode), data.frequentRoutes);

class AnalyticsHeatmap {
  final List<AnalyticsHeatPoint> points;
  final double maxWeight;
  const AnalyticsHeatmap(this.points, this.maxWeight);

  bool get isEmpty => points.isEmpty;
}

class AnalyticsWeeklyHeatmapViewModel {
  final String label;
  final List<int> tripIds;
  final AnalyticsHeatmap heatmap;

  const AnalyticsWeeklyHeatmapViewModel({
    required this.label,
    required this.tripIds,
    required this.heatmap,
  });
}

AnalyticsHeatmap buildAnalyticsHeatmap(Analytics data) {
  return buildHeatmapFromPoints(data.heatmap);
}

AnalyticsHeatmap buildHeatmapFromPoints(List<AnalyticsHeatPoint> points) {
  final maxWeight = points.fold<double>(
    0,
    (max, point) => point.weight > max ? point.weight : max,
  );
  return AnalyticsHeatmap(points, maxWeight);
}

List<AnalyticsWeeklyHeatmapViewModel> buildWeeklyHeatmaps(Analytics data) => [
  for (final week in data.weeklyHeatmaps)
    AnalyticsWeeklyHeatmapViewModel(
      label: week.label,
      tripIds: week.tripIds,
      heatmap: buildHeatmapFromPoints(week.habitualPlaces),
    ),
];

List<AnalyticsBar> analyticsBars(Analytics data) {
  return [
    for (final bucket in data.buckets)
      AnalyticsBar(bucket.label, [
        for (final category in kMobilityCategories)
          _sliceSeconds(bucket, category.key),
      ]),
  ];
}

bool analyticsNeedsWindowSlider(
  int bucketCount, {
  int windowSize = kAnalyticsWindowSize,
}) => bucketCount > windowSize;

int analyticsWindowMaxStart(
  int bucketCount, {
  int windowSize = kAnalyticsWindowSize,
}) {
  if (bucketCount <= windowSize) return 0;
  return bucketCount - windowSize;
}

int analyticsDefaultWindowStart(
  int bucketCount, {
  int windowSize = kAnalyticsWindowSize,
}) => analyticsWindowMaxStart(bucketCount, windowSize: windowSize);

List<T> analyticsWindow<T>(
  List<T> items,
  int start, {
  int windowSize = kAnalyticsWindowSize,
}) {
  if (items.isEmpty) return const [];
  final maxStart = analyticsWindowMaxStart(
    items.length,
    windowSize: windowSize,
  );
  final safeStart = start.clamp(0, maxStart).toInt();
  final end = (safeStart + windowSize).clamp(0, items.length).toInt();
  return items.sublist(safeStart, end);
}

double _sliceSeconds(AnalyticsBucket bucket, String key) {
  for (final slice in bucket.categories) {
    if (slice.category == key) return slice.seconds;
  }
  return 0;
}

AnalyticsTotals calculateAnalyticsTotals(Iterable<AnalyticsBucket> buckets) {
  final seconds = {for (final c in kMobilityCategories) c.key: 0.0};
  final meters = {for (final c in kMobilityCategories) c.key: 0.0};

  for (final bucket in buckets) {
    for (final slice in bucket.categories) {
      if (!seconds.containsKey(slice.category)) continue;
      seconds[slice.category] = seconds[slice.category]! + slice.seconds;
      meters[slice.category] = meters[slice.category]! + slice.distanceMeters;
    }
  }

  final categoryTotals = [
    for (final c in kMobilityCategories)
      AnalyticsCategoryTotal(
        c,
        Duration(seconds: seconds[c.key]!.round()),
        meters[c.key]!,
      ),
  ];
  final movementTime = categoryTotals
      .where((total) => total.category.key != 'fermo')
      .fold(Duration.zero, (sum, total) => sum + total.time);

  return AnalyticsTotals(
    movementTime: movementTime,
    totalDistanceMeters: meters.values.fold(0.0, (a, b) => a + b),
    categoryTotals: categoryTotals,
  );
}
