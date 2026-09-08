import 'package:diary/model/entities/acquisition/acquisition_domain.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit_state.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_error_presenter.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:diary/theme/semantic_colors.dart';
import 'package:diary/ui/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Intestazione del bottom sheet della home: stato dei sensori e pulsante
/// start/stop del viaggio.
class TrackingHeader extends StatefulWidget {
  final AcquisitionCubitState state;

  const TrackingHeader({required this.state, super.key});

  @override
  State<TrackingHeader> createState() => _TrackingHeaderState();
}

class _TrackingHeaderState extends State<TrackingHeader> {
  bool _isHandlingTap = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final semantic =
        Theme.of(context).extension<SemanticColors>() ?? SemanticColors.light;
    final statusColor = state.isTracking
        ? semantic.success
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return SurfaceCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius:
                  BorderRadius.circular(Dimensions.borderRadiusMedium),
            ),
            child: Icon(
              state.isTracking ? Icons.sensors : Icons.sensors_off,
              color: statusColor,
            ),
          ),
          const SizedBox(width: Dimensions.paddingMedium),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.trackingState.wireName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  state.isTracking ? 'sensori attivi' : 'sensori fermi',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: state.isTransitioning || _isHandlingTap
                ? null
                : () => _toggleTracking(context, state),
            icon: state.isTransitioning || _isHandlingTap
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(state.isTracking ? Icons.stop : Icons.play_arrow),
            label: Text(
              state.isTransitioning || _isHandlingTap
                  ? (state.isTracking ? 'Arresto...' : 'Avvio...')
                  : (state.isTracking ? 'Stop' : 'Start'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleTracking(
    BuildContext context,
    AcquisitionCubitState state,
  ) async {
    if (_isHandlingTap || state.isTransitioning) return;
    setState(() => _isHandlingTap = true);
    final cubit = context.read<AcquisitionCubit>();
    final semantic =
        Theme.of(context).extension<SemanticColors>() ?? SemanticColors.light;
    final colorScheme = Theme.of(context).colorScheme;
    try {
      if (state.isTracking) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chiusura viaggio in corso...')),
        );
        await cubit.stopTracking();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Viaggio salvato. Sincronizzazione in background.',
              ),
              backgroundColor: semantic.info,
            ),
          );
        }
      } else {
        await cubit.startTracking();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Acquisizione avviata con successo.'),
              backgroundColor: semantic.success,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(trackingErrorMessage(e)),
            backgroundColor: colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isHandlingTap = false);
    }
  }
}
