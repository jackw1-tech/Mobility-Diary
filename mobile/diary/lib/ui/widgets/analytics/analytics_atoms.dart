
import 'package:diary/theme/dimensions.dart';
import 'package:diary/ui/pages/analytics_presenter.dart';
import 'package:flutter/material.dart';


class AnalyticsDot extends StatelessWidget {
  final Color color;

  const AnalyticsDot({required this.color, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class AnalyticsSectionEmpty extends StatelessWidget {
  final String text;

  const AnalyticsSectionEmpty({required this.text, super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context)
          .textTheme
          .bodyMedium
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

class AnalyticsStatRow extends StatelessWidget {
  final String label;
  final String value;

  const AnalyticsStatRow({
    required this.label,
    required this.value,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Dimensions.paddingXSmall),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class AnalyticsDotStatRow extends StatelessWidget {
  final Color color;
  final String label;
  final String value;

  const AnalyticsDotStatRow({
    required this.color,
    required this.label,
    required this.value,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Dimensions.paddingXSmall),
      child: Row(
        children: [
          AnalyticsDot(color: color),
          const SizedBox(width: Dimensions.paddingSmall),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class AnalyticsCategoryLegend extends StatelessWidget {
  const AnalyticsCategoryLegend({super.key});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Dimensions.paddingMedium,
      runSpacing: Dimensions.paddingSmall,
      children: [
        for (final category in kMobilityCategories)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnalyticsDot(color: category.color),
              const SizedBox(width: Dimensions.paddingXSmall),
              Text(category.label,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
      ],
    );
  }
}
