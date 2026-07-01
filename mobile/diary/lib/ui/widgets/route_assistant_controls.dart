import 'package:diary/features/route_assistant/domain/route_assistant_domain.dart';
import 'package:diary/state_management/cubits/route_assistant_cubit/route_assistant_cubit.dart';
import 'package:diary/state_management/cubits/route_assistant_cubit/route_assistant_cubit_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Colori funzionali dell'assistente (fuori dal brand monocromatico).
const Color routeAssistantRouteColor = Color(0xFF7C4DFF); // viola percorso
const Color _selectedManualColor = Color(0xFF4FC3F7); // azzurrino manuale
const Color _detectedColor = Color(0xFFFFD54F); // giallo modalita' rilevata

/// Stack verticale di selettori in alto a sinistra, visibile solo con un
/// percorso attivo. `liveEnabled` gate del pulsante Live (calcolato dal parent
/// in base al Viaggio in Corso), cosi' il widget resta disaccoppiato e testabile.
class RouteAssistantControls extends StatelessWidget {
  final bool liveEnabled;

  const RouteAssistantControls({this.liveEnabled = false, super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RouteAssistantCubit, RouteAssistantState>(
      builder: (context, state) {
        if (!state.isActive) return const SizedBox.shrink();
        final cubit = context.read<RouteAssistantCubit>();
        return Positioned(
          left: 8,
          top: 8,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ControlButton(
                  icon: Icons.close,
                  tooltip: 'Chiudi assistente',
                  onPressed: cubit.dismiss,
                ),
                _ControlButton(
                  icon: Icons.bolt,
                  tooltip: liveEnabled
                      ? 'Live'
                      : 'Live (serve un viaggio in corso)',
                  background: state.isLive ? _selectedManualColor : null,
                  onPressed: liveEnabled ? cubit.toggleLive : null,
                ),
                _modeButton(cubit, state, RouteMode.walking, Icons.directions_walk),
                _modeButton(cubit, state, RouteMode.cycling, Icons.directions_bike),
                _modeButton(cubit, state, RouteMode.driving, Icons.directions_car),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _modeButton(
    RouteAssistantCubit cubit,
    RouteAssistantState state,
    RouteMode mode,
    IconData icon,
  ) {
    // In Live i chip sono disabilitati e la modalita' rilevata e' gialla;
    // altrimenti il chip manuale selezionato e' azzurrino.
    final highlighted =
        state.isLive ? state.detectedMode == mode : state.mode == mode;
    final background = highlighted
        ? (state.isLive ? _detectedColor : _selectedManualColor)
        : null;
    return _ControlButton(
      icon: icon,
      tooltip: mode.name,
      background: background,
      onPressed: state.isLive ? null : () => cubit.setMode(mode),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? background;

  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: background ?? Colors.white,
        shape: const CircleBorder(),
        elevation: 2,
        child: IconButton(
          icon: Icon(icon),
          tooltip: tooltip,
          color: onPressed == null ? Colors.black26 : Colors.black87,
          onPressed: onPressed,
        ),
      ),
    );
  }
}
