import 'package:diary/theme/dimensions.dart';
import 'package:diary/ui/pages/trip_diary_presenter.dart';
import 'package:flutter/material.dart';

/// Bottom sheet aperto toccando un segmento sulla mappa del viaggio.
class SegmentDetailsSheet extends StatelessWidget {
  final Color color;
  final String activityLabel;
  final double distanceMeters;
  final DateTime startTimestamp;
  final DateTime endTimestamp;

  const SegmentDetailsSheet({
    required this.color,
    required this.activityLabel,
    required this.distanceMeters,
    required this.startTimestamp,
    required this.endTimestamp,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final duration = endTimestamp.difference(startTimestamp);
    final secondaryColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Dimensions.paddingLarge,
        Dimensions.paddingSmall,
        Dimensions.paddingLarge,
        Dimensions.paddingLarge,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Segmento del diario',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: secondaryColor,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: Dimensions.paddingSmall),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: Dimensions.paddingMedium),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activityLabel,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Il sistema ha riconosciuto questo tratto come $activityLabel.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: secondaryColor,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Dimensions.paddingMedium),
          _DetailRow(
            icon: Icons.schedule,
            label: 'Orario',
            value:
                '${_clock(startTimestamp)} - ${_clock(endTimestamp)} (${formatDuration(duration)})',
          ),
          const SizedBox(height: Dimensions.paddingSmall),
          _DetailRow(
            icon: Icons.route,
            label: 'Distanza',
            value: formatDistance(distanceMeters),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final secondaryColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return Row(
      children: [
        Icon(icon, size: 18, color: secondaryColor),
        const SizedBox(width: Dimensions.paddingSmall),
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: secondaryColor,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );
  }
}

String _clock(DateTime time) {
  final local = time.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
