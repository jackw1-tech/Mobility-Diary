import 'package:diary/theme/semantic_colors.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:diary/ui/pages/analytics_presenter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class TimeByCategoryChart extends StatelessWidget {
  final List<AnalyticsBar> bars;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  const TimeByCategoryChart({
    required this.bars,
    required this.selectedIndex,
    required this.onSelect,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final sem = Theme.of(context).extension<SemanticColors>()!;
    final trackTop = _trackTop();
    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: false),
          barTouchData: BarTouchData(
            enabled: true,
            handleBuiltInTouches: false,
            allowTouchBarBackDraw: true,
            touchExtraThreshold:
                const EdgeInsets.symmetric(horizontal: Dimensions.paddingSmall),
            touchCallback: (event, response) {
              if (event is FlTapUpEvent && response?.spot != null) {
                onSelect(response!.spot!.touchedBarGroupIndex);
              }
            },
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (value, _) => Padding(
                  padding: const EdgeInsets.only(top: Dimensions.paddingXSmall),
                  child: Text(
                    _labelAt(value.toInt()),
                    style: TextStyle(
                      fontSize: 10,
                      color: value.toInt() == selectedIndex
                          ? colorScheme.onSurface
                          : colorScheme.onSurfaceVariant,
                      fontWeight: value.toInt() == selectedIndex
                          ? FontWeight.w700
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < bars.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  _rod(bars[i], dimmed: i != selectedIndex, trackTop: trackTop, sem: sem),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _labelAt(int index) =>
      index >= 0 && index < bars.length ? bars[index].label : '';

  double _barMinutes(AnalyticsBar bar) =>
      bar.secondsByCategory.fold<double>(0, (sum, s) => sum + s) / 60.0;

  double _trackTop() {
    final maxMinutes = bars.fold<double>(0, (m, b) {
      final total = _barMinutes(b);
      return total > m ? total : m;
    });
    return maxMinutes <= 0 ? 1.0 : maxMinutes;
  }

  BarChartRodData _rod(
    AnalyticsBar bar, {
    required bool dimmed,
    required double trackTop,
    required SemanticColors sem,
  }) {
    final stack = <BarChartRodStackItem>[];
    var from = 0.0;
    for (var c = 0; c < kMobilityCategories.length; c++) {
      final minutes = bar.secondsByCategory[c] / 60.0;
      if (minutes <= 0) continue;
      final color = kMobilityCategories[c].color;
      stack.add(BarChartRodStackItem(
        from,
        from + minutes,
        dimmed ? color.withValues(alpha: 0.30) : color,
      ));
      from += minutes;
    }
    return BarChartRodData(
      toY: from,
      width: 14,
      color: Colors.transparent,
      rodStackItems: stack,
      borderRadius: BorderRadius.circular(2),
      backDrawRodData: BackgroundBarChartRodData(
        show: true,
        toY: trackTop,
        color:
            dimmed ? sem.surfaceSofter : sem.surfacePressed,
      ),
    );
  }
}
