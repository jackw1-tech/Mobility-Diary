import 'package:diary/theme/dimensions.dart';
import 'package:diary/ui/pages/analytics_presenter.dart';
import 'package:diary/ui/pages/trip_diary_presenter.dart'
    show formatDistance, formatDuration;
import 'package:diary/ui/widgets/analytics/analytics_atoms.dart';
import 'package:flutter/material.dart';

class AnalyticsBucketDetail extends StatelessWidget {
  final String title;
  final AnalyticsTotals totals;

  const AnalyticsBucketDetail({
    required this.title,
    required this.totals,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final active = totals.categoryTotals.where(
      (total) => total.time > Duration.zero,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: Dimensions.paddingXSmall),
        AnalyticsStatRow(
          label: 'In movimento',
          value: totals.movementTime == Duration.zero
              ? '0 min'
              : formatDuration(totals.movementTime),
        ),
        AnalyticsStatRow(
          label: 'Distanza',
          value: formatDistance(totals.totalDistanceMeters),
        ),
        if (active.isNotEmpty) const Divider(height: Dimensions.paddingLarge),
        for (final total in active)
          AnalyticsDotStatRow(
            color: total.category.color,
            label: total.category.label,
            value: formatDuration(total.time),
          ),
      ],
    );
  }
}
