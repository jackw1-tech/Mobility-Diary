import 'package:diary/theme/dimensions.dart';
import 'package:diary/ui/pages/analytics_presenter.dart';
import 'package:diary/ui/widgets/analytics/analytics_atoms.dart';
import 'package:flutter/material.dart';

/// Sezione "Abitudini di sempre": modalita' prevalente e tratte ricorrenti.
class AnalyticsHabitsContent extends StatelessWidget {
  final AnalyticsHabits habits;

  const AnalyticsHabitsContent({required this.habits, super.key});

  @override
  Widget build(BuildContext context) {
    final prevalent = habits.prevalentMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (prevalent != null)
          AnalyticsDotStatRow(
            color: prevalent.color,
            label: 'Modalita\' prevalente',
            value: prevalent.label,
          ),
        if (prevalent != null && habits.routes.isNotEmpty)
          const Divider(height: Dimensions.paddingLarge),
        for (final route in habits.routes)
          AnalyticsStatRow(
            label: '${route.originLabel} → ${route.destinationLabel}',
            value: '×${route.tripCount}',
          ),
      ],
    );
  }
}
