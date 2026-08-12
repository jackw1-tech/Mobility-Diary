import 'package:diary/theme/dimensions.dart';
import 'package:diary/ui/pages/analytics_presenter.dart';
import 'package:diary/ui/widgets/analytics/analytics_atoms.dart';
import 'package:diary/ui/widgets/analytics_heatmap_map.dart';
import 'package:flutter/material.dart';

/// Sezione "Luoghi piu' frequentati": una heatmap per settimana, toccabile per
/// aprirla a tutto schermo.
class AnalyticsWeeklyHeatmaps extends StatelessWidget {
  final List<AnalyticsWeeklyHeatmapViewModel> weeks;

  const AnalyticsWeeklyHeatmaps({required this.weeks, super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < weeks.length; i++) ...[
          _WeeklyHeatmapCard(week: weeks[i]),
          if (i != weeks.length - 1)
            const Divider(height: Dimensions.paddingLarge),
        ],
      ],
    );
  }
}

class _WeeklyHeatmapCard extends StatelessWidget {
  final AnalyticsWeeklyHeatmapViewModel week;

  const _WeeklyHeatmapCard({required this.week});

  @override
  Widget build(BuildContext context) {
    final heatmap = week.heatmap;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Settimana del ${week.label}',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: Dimensions.paddingXSmall),
        const SizedBox(height: Dimensions.paddingSmall),
        if (heatmap.isEmpty)
          const AnalyticsSectionEmpty(
            text:
                'Nessun habitual place associato ai viaggi di questa settimana',
          )
        else
          SizedBox(
            height: 220,
            child: ClipRRect(
              borderRadius:
                  BorderRadius.circular(Dimensions.borderRadiusMedium),
              child: AnalyticsHeatmapMap(
                heatmap: heatmap,
                onTap: () => _openHeatmap(context),
              ),
            ),
          ),
      ],
    );
  }

  void _openHeatmap(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AnalyticsHeatmapMapPage(
          title: 'Settimana del ${week.label}',
          heatmap: week.heatmap,
        ),
      ),
    );
  }
}
