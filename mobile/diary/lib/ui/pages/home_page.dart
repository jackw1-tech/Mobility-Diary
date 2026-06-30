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

class _AuthenticatedHomePage extends StatelessWidget {
  final String? userLabel;

  const _AuthenticatedHomePage({required this.userLabel});

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
              previous.completedReplayTripId == null &&
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
              title: Text(userLabel == null ? 'Mobile Edge' : userLabel!),
              actions: [
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
            body: Stack(
              children: [
                const Positioned.fill(child: LiveMap()),
                DraggableScrollableSheet(
                  initialChildSize: 0.30,
                  minChildSize: 0.12,
                  maxChildSize: 0.9,
                  builder: (context, scrollController) {
                    return DecoratedBox(
                      decoration: const BoxDecoration(
                        color: ColorPalette.background,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(Dimensions.borderRadiusLarge),
                        ),
                        border: Border(
                          top: BorderSide(color: ColorPalette.hairline),
                        ),
                      ),
                      child: ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(Dimensions.paddingMedium),
                        children: [
                          const _SheetHandle(),
                          const SizedBox(height: Dimensions.paddingSmall),
                          _TrackingHeader(state: state),
                          if (state.syncSnapshot.hasJob) ...[
                            const SizedBox(height: Dimensions.paddingMedium),
                            _SyncStatusPanel(state: state),
                          ],
                          const SizedBox(height: Dimensions.paddingMedium),
                          _CoreMetrics(state: state),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
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
          if (state.snapshot.replaySecondsRemaining != null) ...[
            Text(
              'Fine tra ${state.snapshot.replaySecondsRemaining}s',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: ColorPalette.warning,
                  ),
            ),
            const SizedBox(width: Dimensions.paddingSmall),
          ],
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

class _SyncStatusPanel extends StatelessWidget {
  final AcquisitionCubitState state;

  const _SyncStatusPanel({required this.state});

  @override
  Widget build(BuildContext context) {
    final sync = state.syncSnapshot;
    final data = _syncStatusData(sync.status);
    final nextRetryAt = sync.nextRetryAt;

    return _Panel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SyncStatusIcon(sync: sync, data: data),
          const SizedBox(width: Dimensions.paddingSmall),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  _syncSubtitle(sync),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: ColorPalette.textSecondary,
                      ),
                ),
                if (sync.lastError != null && sync.isFailed) ...[
                  const SizedBox(height: 4),
                  Text(
                    sync.lastError!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ColorPalette.error,
                        ),
                  ),
                ],
                if (nextRetryAt != null &&
                    sync.status == AcquisitionSyncStatus.failedRetryable) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Retry dopo ${_formatTime(nextRetryAt)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: ColorPalette.textSecondary,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (sync.canRetry)
            TextButton.icon(
              onPressed: () => context.read<AcquisitionCubit>().resumeSync(),
              icon: const Icon(Icons.refresh),
              label: const Text('Riprova'),
            ),
          if (sync.isNonRecoverable)
            IconButton(
              tooltip: 'Nascondi avviso',
              onPressed: () =>
                  context.read<AcquisitionCubit>().dismissNonRecoverableSync(),
              icon: const Icon(Icons.close),
            ),
          if (sync.canOpenCoreDetail)
            TextButton.icon(
              onPressed: () => context.router.push(
                TripDetailRoute(tripId: sync.remoteTripId!),
              ),
              icon: const Icon(Icons.route),
              label: const Text('Dettaglio'),
            ),
        ],
      ),
    );
  }

  _SyncStatusData _syncStatusData(AcquisitionSyncStatus status) {
    switch (status) {
      case AcquisitionSyncStatus.none:
        return const _SyncStatusData(
          title: 'Nessuna sincronizzazione',
          icon: Icons.cloud_off,
          color: ColorPalette.textSecondary,
        );
      case AcquisitionSyncStatus.pending:
        return const _SyncStatusData(
          title: 'Sync in coda',
          icon: Icons.schedule,
          color: ColorPalette.info,
        );
      case AcquisitionSyncStatus.packaging:
        return const _SyncStatusData(
          title: 'Preparazione pacchetto',
          icon: Icons.inventory_2,
          color: ColorPalette.info,
        );
      case AcquisitionSyncStatus.uploading:
        return const _SyncStatusData(
          title: 'Upload viaggio',
          icon: Icons.cloud_upload,
          color: ColorPalette.info,
        );
      case AcquisitionSyncStatus.waitingProcessing:
        return const _SyncStatusData(
          title: 'Analisi backend',
          icon: Icons.manage_search,
          color: ColorPalette.warning,
        );
      case AcquisitionSyncStatus.completed:
        return const _SyncStatusData(
          title: 'Viaggio sincronizzato',
          icon: Icons.cloud_done,
          color: ColorPalette.success,
        );
      case AcquisitionSyncStatus.failedRetryable:
        return const _SyncStatusData(
          title: 'Sync in attesa',
          icon: Icons.sync_problem,
          color: ColorPalette.warning,
        );
      case AcquisitionSyncStatus.failedFinal:
        return const _SyncStatusData(
          title: 'Viaggio non recuperabile',
          icon: Icons.error_outline,
          color: ColorPalette.error,
        );
    }
  }

  String _syncSubtitle(AcquisitionSyncSnapshot sync) {
    final ingestion = sync.remoteIngestionId == null
        ? null
        : 'ingestion #${sync.remoteIngestionId}';
    final attemptText =
        sync.attempts == 0 ? null : 'tentativo ${sync.attempts}';

    switch (sync.status) {
      case AcquisitionSyncStatus.none:
        return 'Nessun viaggio da caricare';
      case AcquisitionSyncStatus.pending:
        return 'Il viaggio e salvato localmente e aspetta la rete';
      case AcquisitionSyncStatus.packaging:
        return 'Compressione e divisione dei dati in parti';
      case AcquisitionSyncStatus.uploading:
        return ingestion == null
            ? 'Caricamento delle parti compresse'
            : 'Caricamento parti su $ingestion';
      case AcquisitionSyncStatus.waitingProcessing:
        return ingestion == null
            ? 'Dati caricati, elaborazione asincrona in corso'
            : 'Dati caricati, $ingestion in elaborazione';
      case AcquisitionSyncStatus.completed:
        return ingestion == null
            ? 'Dati disponibili sul backend'
            : '$ingestion completata';
      case AcquisitionSyncStatus.failedRetryable:
        return attemptText == null
            ? 'Errore temporaneo, verra ritentato'
            : 'Errore temporaneo, $attemptText';
      case AcquisitionSyncStatus.failedFinal:
        return attemptText == null
            ? 'La chiusura e fallita definitivamente'
            : 'Chiusura fallita definitivamente dopo $attemptText';
    }
  }

  String _formatTime(DateTime time) {
    final localTime = time.toLocal();
    return '${localTime.hour.toString().padLeft(2, '0')}:'
        '${localTime.minute.toString().padLeft(2, '0')}';
  }
}

class _SyncStatusIcon extends StatelessWidget {
  final AcquisitionSyncSnapshot sync;
  final _SyncStatusData data;

  const _SyncStatusIcon({
    required this.sync,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: data.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(Dimensions.borderRadiusSmall),
        ),
        child: Center(
          child: sync.isWorking
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: data.color,
                  ),
                )
              : Icon(data.icon, color: data.color),
        ),
      ),
    );
  }
}

class _SyncStatusData {
  final String title;
  final IconData icon;
  final Color color;

  const _SyncStatusData({
    required this.title,
    required this.icon,
    required this.color,
  });
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
