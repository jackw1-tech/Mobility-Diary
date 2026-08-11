import 'package:diary/theme/color_palette.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:diary/ui/pages/trip_diary_presenter.dart';
import 'package:flutter/material.dart';

/// Banner in cima alla mappa che racconta lo stato dell'arricchimento AI del
/// diario (in corso oppure fallito).
class EnrichmentBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;
  final bool showProgress;

  const EnrichmentBanner({
    required this.icon,
    required this.color,
    required this.message,
    this.showProgress = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: Dimensions.paddingMedium,
      top: Dimensions.paddingMedium,
      right: Dimensions.paddingMedium,
      child: Material(
        color: ColorPalette.surface,
        elevation: Dimensions.cardElevation,
        borderRadius: BorderRadius.circular(Dimensions.borderRadiusMedium),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Dimensions.borderRadiusMedium),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showProgress) const LinearProgressIndicator(minHeight: 3),
              Padding(
                padding: const EdgeInsets.all(Dimensions.paddingSmall),
                child: Row(
                  children: [
                    Icon(icon, color: color, size: 18),
                    const SizedBox(width: Dimensions.paddingSmall),
                    Expanded(
                      child: Text(
                        message,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Selettore traccia intera / segmenti, visibile solo a viaggio segmentato.
class ViewModeToggle extends StatelessWidget {
  final bool showSegments;
  final ValueChanged<bool> onChanged;

  const ViewModeToggle({
    required this.showSegments,
    required this.onChanged,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ColorPalette.surface,
      elevation: Dimensions.cardElevation,
      borderRadius: BorderRadius.circular(Dimensions.borderRadiusLarge),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              icon: Icon(Icons.timeline),
              label: Text('Traccia'),
            ),
            ButtonSegment(
              value: true,
              icon: Icon(Icons.route),
              label: Text('Segmenti'),
            ),
          ],
          selected: {showSegments},
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
      ),
    );
  }
}

/// Pillola in basso con la distanza totale del viaggio.
class DistanceOverlay extends StatelessWidget {
  final double distanceMeters;

  const DistanceOverlay({required this.distanceMeters, super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(Dimensions.borderRadiusLarge),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(Dimensions.paddingMedium),
        child: Row(
          children: [
            const Icon(Icons.route, color: ColorPalette.primary),
            const SizedBox(width: Dimensions.paddingSmall),
            Text(
              formatDistance(distanceMeters),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
