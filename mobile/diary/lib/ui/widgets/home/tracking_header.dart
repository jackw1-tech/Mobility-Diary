import 'package:diary/model/entities/acquisition/acquisition_domain.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit_state.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_error_presenter.dart';
import 'package:diary/theme/color_palette.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:diary/ui/widgets/home/fsm_diagnostics_report_sheet.dart';
import 'package:diary/ui/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Intestazione del bottom sheet della home: stato dei sensori e pulsante
/// start/stop del viaggio.
class TrackingHeader extends StatelessWidget {
  final AcquisitionCubitState state;

  const TrackingHeader({required this.state, super.key});

  @override
  Widget build(BuildContext context) {
    final statusColor =
        state.isTracking ? ColorPalette.success : ColorPalette.textSecondary;

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
                        color: ColorPalette.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: () => _toggleTracking(context, state),
            icon: Icon(state.isTracking ? Icons.stop : Icons.play_arrow),
            label: Text(state.isTracking ? 'Stop' : 'Start'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleTracking(
    BuildContext context,
    AcquisitionCubitState state,
  ) async {
    final cubit = context.read<AcquisitionCubit>();
    try {
      if (state.isTracking) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chiusura viaggio in corso...')),
        );
        final diagnosticsReport = await cubit.stopTracking();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Viaggio salvato. Sincronizzazione in background.'),
              backgroundColor: ColorPalette.info,
            ),
          );
          if (diagnosticsReport != null) {
            await showFsmDiagnosticsReportSheet(context, diagnosticsReport);
          } else if (!state.isReplay) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Viaggio salvato, ma il file diagnostico non è disponibile.',
                ),
                backgroundColor: ColorPalette.warning,
              ),
            );
          }
        }
      } else {
        await cubit.startTracking();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Acquisizione avviata con successo.'),
              backgroundColor: ColorPalette.success,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(trackingErrorMessage(e)),
            backgroundColor: ColorPalette.error,
          ),
        );
      }
    }
  }
}
