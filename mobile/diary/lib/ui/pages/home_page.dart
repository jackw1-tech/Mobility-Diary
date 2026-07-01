import 'package:auto_route/auto_route.dart';
import 'package:diary/features/acquisition/domain/acquisition_domain.dart';
import 'package:diary/network/service/privacy_settings_service.dart';
import 'package:diary/repositories/acquisition_repository.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit_state.dart';
import 'package:diary/state_management/cubits/auth_cubit/auth_cubit.dart';
import 'package:diary/state_management/cubits/auth_cubit/auth_cubit_state.dart';
import 'package:diary/state_management/cubits/privacy_settings_cubit/privacy_settings_cubit.dart';
import 'package:diary/routers/app_router.dart';
import 'package:diary/theme/Dimensions.dart';
import 'package:diary/theme/color_palette.dart';
import 'package:diary/ui/pages/auth_page.dart';
import 'package:diary/ui/widgets/live_map.dart';
import 'package:diary/ui/widgets/privacy_onboarding_dialog.dart';
import 'package:diary/ui/widgets/route_assistant_search_sheet.dart';
import 'package:diary/ui/widgets/trips_drawer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

@RoutePage()
class HomePage extends StatelessWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthCubit, AuthCubitState>(
      builder: (context, authState) {
        if (authState.status == AuthStatus.initial ||
            authState.status == AuthStatus.loading) {
          return const _AuthLoadingPage();
        }

        if (!authState.isAuthenticated) {
          return const AuthPage();
        }

        return BlocProvider<PrivacySettingsCubit>(
          create: (context) => PrivacySettingsCubit(
            context.read<PrivacySettingsService>(),
          )..load(),
          child: _AuthenticatedHomePage(userLabel: authState.user?.displayName),
        );
      },
    );
  }
}

class _AuthenticatedHomePage extends StatefulWidget {
  final String? userLabel;

  const _AuthenticatedHomePage({required this.userLabel});

  @override
  State<_AuthenticatedHomePage> createState() => _AuthenticatedHomePageState();
}

class _AuthenticatedHomePageState extends State<_AuthenticatedHomePage> {
  static const double _initialSheetExtent = 0.30;
  static const double _minSheetExtent = 0.05;
  static const double _maxSheetExtent = 0.38;

  double _sheetExtent = _initialSheetExtent;

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<PrivacySettingsCubit, PrivacySettingsState>(
          listenWhen: (previous, current) => current.needsPrivacyOnboarding,
          listener: (context, state) => showPrivacyOnboardingDialog(context),
        ),
        BlocListener<AcquisitionCubit, AcquisitionCubitState>(
          listenWhen: (previous, current) =>
              !previous.syncSnapshot.canOpenCoreDetail &&
              current.syncSnapshot.canOpenCoreDetail,
          listener: (context, state) {
            final tripId = state.syncSnapshot.remoteTripId;
            if (tripId != null) {
              context.router.push(TripDetailRoute(tripId: tripId));
            }
          },
        ),
        BlocListener<AcquisitionCubit, AcquisitionCubitState>(
          listenWhen: (previous, current) =>
              previous.completedReplayTripId != current.completedReplayTripId &&
              current.completedReplayTripId != null,
          listener: (context, state) {
            final tripId = state.completedReplayTripId;
            if (tripId != null) {
              context.router.push(TripDetailRoute(tripId: tripId));
            }
          },
        ),
      ],
      child: BlocBuilder<AcquisitionCubit, AcquisitionCubitState>(
        builder: (context, state) {
          return Scaffold(
            drawer: const TripsDrawer(),
            appBar: AppBar(
              centerTitle: true,
              title: Text(
                widget.userLabel == null ? 'Mobile Edge' : widget.userLabel!,
              ),
              actions: [
                IconButton(
                  tooltip: 'Assistente percorso',
                  icon: const Icon(Icons.alt_route),
                  onPressed: () => showRouteAssistantSearch(context),
                ),
                IconButton(
                  tooltip: 'Statistiche',
                  icon: const Icon(Icons.insights_outlined),
                  onPressed: () => context.router.push(const AnalyticsRoute()),
                ),
                IconButton(
                  tooltip: 'I miei luoghi',
                  icon: const Icon(Icons.place_outlined),
                  onPressed: () => context.router.push(const PlacesRoute()),
                ),
              ],
            ),
            body: LayoutBuilder(
              builder: (context, constraints) {
                final replaySecondsRemaining =
                    state.snapshot.replaySecondsRemaining;
                return Stack(
                  children: [
                    const Positioned.fill(child: LiveMap()),
                    if (replaySecondsRemaining != null)
                      Positioned(
                        left: Dimensions.paddingMedium,
                        right: Dimensions.paddingMedium,
                        bottom: constraints.maxHeight * _sheetExtent +
                            Dimensions.paddingSmall,
                        child: _ReplayCountdownPill(
                          seconds: replaySecondsRemaining,
                        ),
                      ),
                    NotificationListener<DraggableScrollableNotification>(
                      onNotification: (notification) {
                        if ((notification.extent - _sheetExtent).abs() >
                            0.001) {
                          setState(() => _sheetExtent = notification.extent);
                        }
                        return false;
                      },
                      child: DraggableScrollableSheet(
                        initialChildSize: _initialSheetExtent,
                        minChildSize: _minSheetExtent,
                        maxChildSize: _maxSheetExtent,
                        builder: (context, scrollController) {
                          return DecoratedBox(
                            decoration: const BoxDecoration(
                              color: ColorPalette.background,
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(
                                  Dimensions.borderRadiusLarge,
                                ),
                              ),
                              border: Border(
                                top: BorderSide(color: ColorPalette.hairline),
                              ),
                            ),
                            child: ListView(
                              controller: scrollController,
                              padding: const EdgeInsets.all(
                                Dimensions.paddingMedium,
                              ),
                              children: [
                                const _SheetHandle(),
                                const SizedBox(
                                  height: Dimensions.paddingSmall,
                                ),
                                _TrackingHeader(state: state),
                                const SizedBox(
                                  height: Dimensions.paddingMedium,
                                ),
                                _CoreMetrics(state: state),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

int? autoOpenTripDetailId(
  AcquisitionCubitState previous,
  AcquisitionCubitState current,
) {
  final replayTripId = current.completedReplayTripId;
  if (replayTripId != null && previous.completedReplayTripId != replayTripId) {
    return replayTripId;
  }

  final sync = current.syncSnapshot;
  if (!previous.syncSnapshot.canOpenCoreDetail && sync.canOpenCoreDetail) {
    return sync.remoteTripId;
  }

  return null;
}

class _AuthLoadingPage extends StatelessWidget {
  const _AuthLoadingPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: ColorPalette.background,
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _ReplayCountdownPill extends StatelessWidget {
  final int seconds;

  const _ReplayCountdownPill({required this.seconds});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ColorPalette.surface,
          borderRadius: BorderRadius.circular(Dimensions.borderRadiusLarge),
          border: Border.all(color: ColorPalette.warning),
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
              const Icon(
                Icons.timer_outlined,
                color: ColorPalette.warning,
                size: 18,
              ),
              const SizedBox(width: Dimensions.paddingSmall),
              Text(
                'Fine tra ${seconds}s',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: ColorPalette.warning,
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

class _TrackingHeader extends StatelessWidget {
  final AcquisitionCubitState state;

  const _TrackingHeader({required this.state});

  @override
  Widget build(BuildContext context) {
    final statusColor =
        state.isTracking ? ColorPalette.success : ColorPalette.textSecondary;

    return _Panel(
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
        await cubit.stopTracking();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Viaggio salvato. Sincronizzazione in background.'),
              backgroundColor: ColorPalette.info,
            ),
          );
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
            content: Text(_trackingErrorMessage(e)),
            backgroundColor: ColorPalette.error,
          ),
        );
      }
    }
  }
}

String _trackingErrorMessage(Object error) {
  if (error is ActiveTripOnAnotherDeviceException) {
    return error.message;
  }
  if (error is PendingTripSyncException) {
    return error.message;
  }
  if (error is StartRequiresConnectionException) {
    return error.message;
  }
  return 'Errore durante la comunicazione HTTP: $error';
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: ColorPalette.textSecondary.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _CoreMetrics extends StatelessWidget {
  final AcquisitionCubitState state;

  const _CoreMetrics({required this.state});

  @override
  Widget build(BuildContext context) {
    final speedKmh = state.latestSpeedMetersPerSecond * 3.6;

    return Row(
      children: [
        Expanded(
          child: _MetricTile(
            icon: Icons.speed,
            label: 'Sigma',
            value: state.latestSigma.toStringAsFixed(2),
            color: ColorPalette.accent,
          ),
        ),
        const SizedBox(width: Dimensions.paddingSmall),
        Expanded(
          child: _MetricTile(
            icon: Icons.explore,
            label: 'Velocita',
            value: '${speedKmh.toStringAsFixed(1)} km/h',
            color: ColorPalette.info,
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: Dimensions.paddingSmall),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: ColorPalette.textSecondary,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;

  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ColorPalette.surface,
        borderRadius: BorderRadius.circular(Dimensions.borderRadiusLarge),
        border: Border.all(color: ColorPalette.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Dimensions.paddingMedium),
        child: child,
      ),
    );
  }
}
