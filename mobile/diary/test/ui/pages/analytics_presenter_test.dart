import 'package:diary/network/dto/analytics_dto.dart';
import 'package:diary/ui/pages/analytics_presenter.dart';
import 'package:flutter_test/flutter_test.dart';

AnalyticsCategorySliceDto _slice(String category, double seconds, double meters) =>
    AnalyticsCategorySliceDto(
      category: category,
      seconds: seconds,
      distanceMeters: meters,
    );

AnalyticsDto _data(
  List<AnalyticsBucketDto> buckets, {
  List<AnalyticsHeatPointDto> heatmap = const [],
  String? prevalentMode,
  List<AnalyticsRouteDto> routes = const [],
}) =>
    AnalyticsDto(
      granularity: 'day',
      hasData: true,
      buckets: buckets,
      prevalentMode: prevalentMode,
      frequentRoutes: routes,
      heatmap: heatmap,
    );

double _categoryTime(AnalyticsTrend trend, String key) => trend.categoryTotals
    .firstWhere((total) => total.category.key == key)
    .time
    .inSeconds
    .toDouble();

void main() {
  group('buildAnalyticsTrend', () {
    final trend = buildAnalyticsTrend(_data([
      AnalyticsBucketDto(
        label: 'Lun',
        categories: [_slice('a_piedi', 600, 1200), _slice('fermo', 300, 0)],
      ),
      AnalyticsBucketDto(
        label: 'Mar',
        categories: [_slice('in_bici', 900, 2500), _slice('in_auto', 1200, 8000)],
      ),
    ]));

    test('maps one bar per bucket with seconds aligned to category order', () {
      expect(trend.bars.map((b) => b.label), ['Lun', 'Mar']);
      // Ordine: fermo, a_piedi, corsa, in_bici, in_auto.
      expect(trend.bars[0].secondsByCategory, [300, 600, 0, 0, 0]);
      expect(trend.bars[1].secondsByCategory, [0, 0, 0, 900, 1200]);
    });

    test('movementTime sums the non-Fermo categories', () {
      expect(trend.movementTime, const Duration(seconds: 600 + 900 + 1200));
    });

    test('totalDistanceMeters sums every category distance', () {
      expect(trend.totalDistanceMeters, 1200 + 2500 + 8000);
    });

    test('categoryTotals accumulate time and distance per category', () {
      expect(_categoryTime(trend, 'a_piedi'), 600);
      expect(_categoryTime(trend, 'fermo'), 300);
      expect(_categoryTime(trend, 'corsa'), 0);
      final inAuto = trend.categoryTotals
          .firstWhere((total) => total.category.key == 'in_auto');
      expect(inAuto.distanceMeters, 8000);
    });
  });

  group('buildAnalyticsHeatmap', () {
    test('keeps the points and tracks the max weight', () {
      final heatmap = buildAnalyticsHeatmap(_data(const [], heatmap: const [
        AnalyticsHeatPointDto(lat: 45.47, lon: 9.20, weight: 12),
        AnalyticsHeatPointDto(lat: 45.46, lon: 9.10, weight: 4),
      ]));

      expect(heatmap.isEmpty, isFalse);
      expect(heatmap.points, hasLength(2));
      expect(heatmap.maxWeight, 12);
    });

    test('is empty when there are no places', () {
      final heatmap = buildAnalyticsHeatmap(_data(const []));

      expect(heatmap.isEmpty, isTrue);
      expect(heatmap.maxWeight, 0);
    });
  });

  group('buildAnalyticsHabits', () {
    test('resolves the prevalent mode label and keeps the routes', () {
      final habits = buildAnalyticsHabits(_data(
        const [],
        prevalentMode: 'in_bici',
        routes: const [
          AnalyticsRouteDto(
            originLabel: 'Casa',
            destinationLabel: 'Universita',
            tripCount: 2,
          ),
        ],
      ));

      expect(habits.isEmpty, isFalse);
      expect(habits.prevalentMode?.label, 'In bici');
      expect(habits.routes.single.tripCount, 2);
    });

    test('is empty without a prevalent mode nor routes', () {
      final habits = buildAnalyticsHabits(_data(const []));

      expect(habits.isEmpty, isTrue);
      expect(habits.prevalentMode, isNull);
    });
  });
}
