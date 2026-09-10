import 'package:diary/model/entities/route_assistant/route_assistant_domain.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:diary/theme/semantic_colors.dart';
import 'package:flutter/material.dart';

class HomeMapOverlays extends StatelessWidget {
  final RouteAssistantRoute? route;
  final DateTime? routeUpdatedAt;
  final int? replaySecondsRemaining;

  const HomeMapOverlays({
    required this.route,
    required this.routeUpdatedAt,
    required this.replaySecondsRemaining,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (route != null)
          _RouteStatsPanel(
            route: route!,
            routeUpdatedAt: routeUpdatedAt ?? DateTime.now(),
          ),
        if (route != null && replaySecondsRemaining != null)
          const SizedBox(height: Dimensions.paddingSmall),
        if (replaySecondsRemaining != null)
          _ReplayCountdownPill(seconds: replaySecondsRemaining!),
      ],
    );
  }
}

class _RouteStatsPanel extends StatelessWidget {
  final RouteAssistantRoute route;
  final DateTime routeUpdatedAt;

  const _RouteStatsPanel({required this.route, required this.routeUpdatedAt});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = theme.extension<SemanticColors>() ?? SemanticColors.light;
    final primaryColor = theme.colorScheme.primary;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(Dimensions.borderRadiusLarge),
            border: Border.all(color: semantic.hairline),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Dimensions.paddingMedium,
              vertical: Dimensions.paddingSmall,
            ),
            child: Row(
              children: [
                Expanded(
                  child: _RouteStatsItem(
                    icon: Icons.flag_outlined,
                    label: 'Arrivo',
                    value: _arrivalTimeLabel(
                      route.durationSeconds,
                      routeUpdatedAt,
                    ),
                    color: primaryColor,
                  ),
                ),
                const SizedBox(width: Dimensions.paddingSmall),
                Expanded(
                  child: _RouteStatsItem(
                    icon: Icons.straighten,
                    label: 'Mancano',
                    value: _distanceLabel(route.distanceMeters),
                    color: primaryColor,
                  ),
                ),
                const SizedBox(width: Dimensions.paddingSmall),
                Expanded(
                  child: _RouteStatsItem(
                    icon: Icons.schedule,
                    label: 'Tempo',
                    value: _durationLabel(route.durationSeconds),
                    color: primaryColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RouteStatsItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _RouteStatsItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: Dimensions.paddingSmall),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReplayCountdownPill extends StatelessWidget {
  final int seconds;

  const _ReplayCountdownPill({required this.seconds});

  @override
  Widget build(BuildContext context) {
    final semantic =
        Theme.of(context).extension<SemanticColors>() ?? SemanticColors.light;

    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(Dimensions.borderRadiusLarge),
          border: Border.all(color: semantic.warning),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Dimensions.paddingMedium,
            vertical: Dimensions.paddingSmall,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.timer_outlined, color: semantic.warning, size: 18),
              const SizedBox(width: Dimensions.paddingSmall),
              Text(
                'Fine tra ${seconds}s',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: semantic.warning,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _arrivalTimeLabel(double durationSeconds, DateTime routeUpdatedAt) {
  final arrival = routeUpdatedAt.add(
    Duration(seconds: durationSeconds.round()),
  );
  final hour = arrival.hour.toString().padLeft(2, '0');
  final minute = arrival.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _distanceLabel(double distanceMeters) {
  if (distanceMeters < 1000) {
    return '${distanceMeters.round()} m';
  }
  return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
}

String _durationLabel(double durationSeconds) {
  final minutes = (durationSeconds / 60).ceil();
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final remainingMinutes = minutes % 60;
  if (remainingMinutes == 0) return '${hours}h';
  return '${hours}h ${remainingMinutes}m';
}
