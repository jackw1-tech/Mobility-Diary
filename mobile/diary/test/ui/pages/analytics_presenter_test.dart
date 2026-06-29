import 'package:diary/network/dto/analytics_dto.dart';
import 'package:diary/ui/pages/analytics_presenter.dart';
import 'package:flutter_test/flutter_test.dart';

AnalyticsCategorySliceDto _slice(
        String category, double seconds, double meters) =>
    AnalyticsCategorySliceDto(
      category: category,
      seconds: seconds,
      distanceMeters: meters,
    );

AnalyticsDto _data(
  List<AnalyticsBucketDto> buckets, {
  List<AnalyticsHeatPointDto> heatmap = const [],
  List<AnalyticsWeeklyHeatmapDto> weeklyHeatmaps = const [],
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
      weeklyHeatmaps: weeklyHeatmaps,
    );

double _categoryTime(AnalyticsSummary summary, String key) =>
    summary.categoryTotals
        .firstWhere((total) => total.category.key == key)
        .time
        .inSeconds
        .toDouble();

final _twoBuckets = [
  AnalyticsBucketDto(
    label: 'Lun',
    categories: [_slice('a_piedi', 600, 1200), _slice('fermo', 300, 0)],
  ),
  AnalyticsBucketDto(
    label: 'Mar',
    categories: [_slice('in_bici', 900, 2500), _slice('in_auto', 1200, 8000)],
  ),
];

void main() {
  group('analyticsBars', () {
    test('maps one bar per bucket with seconds aligned to category order', () {
      final bars = analyticsBars(_data(_twoBuckets));

      expect(bars.map((b) => b.label), ['Lun', 'Mar']);
      // Ordine: fermo, a_piedi, corsa, in_bici, in_auto.
      expect(bars[0].secondsByCategory, [300, 600, 0, 0, 0]);
      expect(bars[1].secondsByCategory, [0, 0, 0, 900, 1200]);
    });
  });

  group('analyticsWindow helpers', () {
    test('shows the slider only when buckets exceed the window size', () {
      expect(analyticsNeedsWindowSlider(kAnalyticsWindowSize), isFalse);
      expect(analyticsNeedsWindowSlider(kAnalyticsWindowSize + 1), isTrue);
    });

    test(
        'defaults to the latest full window when more than seven buckets exist',
        () {
      expect(analyticsWindowMaxStart(5), 0);
      expect(analyticsWindowMaxStart(10), 3);
      expect(analyticsDefaultWindowStart(10), 3);
    });

    test('returns a clamped window of seven consecutive items', () {
      final items = List.generate(10, (index) => 'B$index');

      expect(analyticsWindow(items, 0),
          ['B0', 'B1', 'B2', 'B3', 'B4', 'B5', 'B6']);
      expect(analyticsWindow(items, 3),
          ['B3', 'B4', 'B5', 'B6', 'B7', 'B8', 'B9']);
      expect(analyticsWindow(items, 99),
          ['B3', 'B4', 'B5', 'B6', 'B7', 'B8', 'B9']);
    });
  });

  group('summarizeBuckets', () {
    test('over the whole window sums movement, distance and per category', () {
      final summary = summarizeBuckets(_twoBuckets);

      expect(summary.movementTime, const Duration(seconds: 600 + 900 + 1200));
      expect(summary.totalDistanceMeters, 1200 + 2500 + 8000);
      expect(_categoryTime(summary, 'a_piedi'), 600);
      expect(_categoryTime(summary, 'fermo'), 300);
      expect(_categoryTime(summary, 'corsa'), 0);
    });

    test('over a single selected bucket reports only that day', () {
      final summary = summarizeBuckets([_twoBuckets[1]]);

      expect(summary.movementTime, const Duration(seconds: 900 + 1200));
      expect(summary.totalDistanceMeters, 2500 + 8000);
      expect(_categoryTime(summary, 'a_piedi'), 0);
      expect(_categoryTime(summary, 'in_bici'), 900);
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

  group('buildWeeklyHeatmaps', () {
    test('keeps weekly trip ids and computes max weight per week', () {
      final weeks = buildWeeklyHeatmaps(_data(
        const [],
        weeklyHeatmaps: const [
          AnalyticsWeeklyHeatmapDto(
            label: '22/06',
            tripIds: [10, 11],
            habitualPlaces: [
              AnalyticsHeatPointDto(lat: 45.47, lon: 9.20, weight: 2),
              AnalyticsHeatPointDto(lat: 45.46, lon: 9.10, weight: 1),
            ],
          ),
        ],
      ));

      expect(weeks, hasLength(1));
      expect(weeks.single.label, '22/06');
      expect(weeks.single.tripIds, [10, 11]);
      expect(weeks.single.heatmap.maxWeight, 2);
      expect(weeks.single.heatmap.points, hasLength(2));
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
