import 'package:diary/model/entities/route_assistant/route_assistant_domain.dart';
import 'package:diary/state_management/cubits/route_assistant_cubit/route_assistant_cubit.dart';
import 'package:diary/state_management/cubits/route_assistant_cubit/route_assistant_cubit_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

const Color routeAssistantRouteColor = Color(0xFF7C4DFF); // viola percorso
const Color _selectedManualColor = Color(0xFF4FC3F7); // azzurrino manuale
const Color _detectedColor = Color(0xFFFFD54F); // giallo modalita' rilevata
const IconData _stationaryModeIcon = Icons.pause;

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
                  tooltip: state.isLive
                      ? 'Spegni Live'
                      : liveEnabled
                      ? 'Live'
                      : 'Live (serve un viaggio in corso)',
                  background: state.isLive ? _selectedManualColor : null,
                  onPressed: state.isLive || liveEnabled
                      ? cubit.toggleLive
                      : null,
                ),
                _modeButton(
                  cubit,
                  state,
                  RouteMode.walking,
                  Icons.directions_walk,
                ),
                _modeButton(
                  cubit,
                  state,
                  RouteMode.cycling,
                  Icons.directions_bike,
                ),
                _modeButton(
                  cubit,
                  state,
                  RouteMode.driving,
                  Icons.directions_car,
                ),
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
    final highlighted = state.isLive
        ? state.detectedMode == mode
        : state.mode == mode;
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

class RouteDetectedModeIndicator extends StatefulWidget {
  final RouteMode? mode;
  final bool hasResult;

  const RouteDetectedModeIndicator({
    required this.mode,
    required this.hasResult,
    super.key,
  });

  @override
  State<RouteDetectedModeIndicator> createState() =>
      _RouteDetectedModeIndicatorState();
}

class _RouteDetectedModeIndicatorState
    extends State<RouteDetectedModeIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseOpacity;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pulseOpacity = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeOut,
    ).drive(Tween(begin: 1.0, end: 0.0));
  }

  @override
  void didUpdateWidget(RouteDetectedModeIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Una nuova classificazione e' arrivata: rifaccio lampeggiare l'anello,
    // anche se il risultato e' identico al precedente (l'utente vuole vedere
    // che il rilevamento e' ancora vivo, non solo quando cambia modalita').
    if (widget.mode != oldWidget.mode ||
        widget.hasResult != oldWidget.hasResult) {
      _pulseController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 8,
      top: 8,
      child: SafeArea(
        child: Tooltip(
          message: _tooltip,
          child: AnimatedBuilder(
            animation: _pulseOpacity,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _detectedColor.withValues(
                        alpha: 0.6 * _pulseOpacity.value,
                      ),
                      blurRadius: 10,
                      spreadRadius: 4 * _pulseOpacity.value,
                    ),
                  ],
                ),
                child: child,
              );
            },
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              shape: const CircleBorder(),
              elevation: 2,
              child: SizedBox.square(
                dimension: 48,
                child: Icon(
                  _icon,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData get _icon {
    if (!widget.hasResult) return Icons.more_horiz;
    switch (widget.mode) {
      case RouteMode.walking:
        return Icons.directions_walk;
      case RouteMode.cycling:
        return Icons.directions_bike;
      case RouteMode.driving:
        return Icons.directions_car;
      case null:
        return _stationaryModeIcon;
    }
  }

  String get _tooltip {
    if (!widget.hasResult) return 'Modalità in rilevamento';
    switch (widget.mode) {
      case RouteMode.walking:
        return 'A piedi';
      case RouteMode.cycling:
        return 'Bici';
      case RouteMode.driving:
        return 'Auto';
      case null:
        return 'Fermo';
    }
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
    final colorScheme = Theme.of(context).colorScheme;
    final surfaceColor = colorScheme.surface;
    final onSurfaceColor = colorScheme.onSurface;
    final hasCustomBg = background != null;

    final iconColor = hasCustomBg
        ? Colors.black87
        : (onPressed == null
              ? onSurfaceColor.withValues(alpha: 0.38)
              : onSurfaceColor);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: background ?? surfaceColor,
        shape: const CircleBorder(),
        elevation: 2,
        child: IconButton(
          icon: Icon(icon),
          tooltip: tooltip,
          color: iconColor,
          onPressed: onPressed,
        ),
      ),
    );
  }
}
