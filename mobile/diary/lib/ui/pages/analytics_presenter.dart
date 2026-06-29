import 'package:diary/network/dto/analytics_dto.dart';
import 'package:flutter/material.dart';

/// Categoria di Mobilita mostrata nel grafico, in ordine di stack. I colori
/// sono allineati a quelli della dashboard web per coerenza cross-piattaforma.
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
  // Secondi per categoria, allineati a kMobilityCategories.
  final List<double> secondsByCategory;
  const AnalyticsBar(this.label, this.secondsByCategory);
}

class AnalyticsCategoryTotal {
  final MobilityCategory category;
  final Duration time;
  final double distanceMeters;
  const AnalyticsCategoryTotal(this.category, this.time, this.distanceMeters);
}

/// Modello di presentazione dell'Andamento recente: barre del grafico +
/// totali della finestra (tempo "In movimento" e distanze per categoria).
class AnalyticsTrend {
  final List<AnalyticsBar> bars;
  final Duration movementTime;
  final double totalDistanceMeters;
  final List<AnalyticsCategoryTotal> categoryTotals;

  const AnalyticsTrend({
    required this.bars,
    required this.movementTime,
    required this.totalDistanceMeters,
    required this.categoryTotals,
  });
}

MobilityCategory? categoryByKey(String? key) {
  for (final category in kMobilityCategories) {
    if (category.key == key) return category;
  }
  return null;
}

/// Abitudini di sempre: modalita' prevalente + Percorsi Frequenti, cumulativi.
class AnalyticsHabits {
  final MobilityCategory? prevalentMode;
  final List<AnalyticsRouteDto> routes;
  const AnalyticsHabits(this.prevalentMode, this.routes);

  bool get isEmpty => prevalentMode == null && routes.isEmpty;
}

AnalyticsHabits buildAnalyticsHabits(AnalyticsDto data) =>
    AnalyticsHabits(categoryByKey(data.prevalentMode), data.frequentRoutes);

/// Mappa di Frequentazione: Luoghi Significativi pesati per visite, cumulativi.
class AnalyticsHeatmap {
  final List<AnalyticsHeatPointDto> points;
  final double maxWeight;
  const AnalyticsHeatmap(this.points, this.maxWeight);

  bool get isEmpty => points.isEmpty;
}

AnalyticsHeatmap buildAnalyticsHeatmap(AnalyticsDto data) {
  final maxWeight = data.heatmap.fold<double>(
    0,
    (max, point) => point.weight > max ? point.weight : max,
  );
  return AnalyticsHeatmap(data.heatmap, maxWeight);
}

AnalyticsTrend buildAnalyticsTrend(AnalyticsDto data) {
  final seconds = {for (final c in kMobilityCategories) c.key: 0.0};
  final meters = {for (final c in kMobilityCategories) c.key: 0.0};

  final bars = <AnalyticsBar>[];
  for (final bucket in data.buckets) {
    final byKey = {for (final s in bucket.categories) s.category: s};
    bars.add(AnalyticsBar(bucket.label, [
      for (final c in kMobilityCategories) byKey[c.key]?.seconds ?? 0,
    ]));
    for (final c in kMobilityCategories) {
      final slice = byKey[c.key];
      if (slice == null) continue;
      seconds[c.key] = seconds[c.key]! + slice.seconds;
      meters[c.key] = meters[c.key]! + slice.distanceMeters;
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

  return AnalyticsTrend(
    bars: bars,
    movementTime: movementTime,
    totalDistanceMeters: meters.values.fold(0.0, (a, b) => a + b),
    categoryTotals: categoryTotals,
  );
}
