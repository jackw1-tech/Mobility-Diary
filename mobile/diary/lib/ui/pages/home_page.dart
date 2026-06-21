import 'package:auto_route/auto_route.dart';
import 'package:diary/features/acquisition/domain/acquisition_domain.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit_state.dart';
import 'package:diary/state_management/cubits/auth_cubit/auth_cubit.dart';
import 'package:diary/state_management/cubits/auth_cubit/auth_cubit_state.dart';
import 'package:diary/routers/app_router.dart';
import 'package:diary/theme/Dimensions.dart';
import 'package:diary/theme/color_palette.dart';
import 'package:diary/ui/pages/auth_page.dart';
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

        return _AuthenticatedHomePage(userLabel: authState.user?.displayName);
      },
    );
  }
}

class _AuthenticatedHomePage extends StatelessWidget {
  final String? userLabel;

  const _AuthenticatedHomePage({required this.userLabel});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AcquisitionCubit, AcquisitionCubitState>(
      builder: (context, state) {
        return Scaffold(
          drawer: const TripsDrawer(),
          appBar: AppBar(
            title: Text(userLabel == null ? 'Mobile Edge' : userLabel!),
            backgroundColor: ColorPalette.primary,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                tooltip: 'Logout',
                onPressed: () => context.read<AuthCubit>().logout(),
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          body: ColoredBox(
            color: ColorPalette.background,
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(Dimensions.paddingMedium),
                children: [
                  _TrackingHeader(state: state),
                  if (state.syncSnapshot.hasJob) ...[
                    const SizedBox(height: Dimensions.paddingMedium),
                    _SyncStatusPanel(state: state),
                  ],
                  const SizedBox(height: Dimensions.paddingMedium),
                  _CoreMetrics(state: state),
                  const SizedBox(height: Dimensions.paddingMedium),
                  _SensorList(state: state),
                  const SizedBox(height: Dimensions.paddingMedium),
                  _LastTransition(state: state),
                  const SizedBox(height: Dimensions.paddingMedium),
                  _LiveMetricList(state: state),
                ],
              ),
            ),
          ),
        );
      },
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
            content: Text('Errore durante la comunicazione HTTP: $e'),
            backgroundColor: ColorPalette.error,
          ),
        );
      }
    }
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
          if (sync.isFailed)
            TextButton.icon(
              onPressed: () => context.read<AcquisitionCubit>().resumeSync(),
              icon: const Icon(Icons.refresh),
              label: const Text('Riprova'),
            ),
          if (sync.canOpenCoreMap)
            TextButton.icon(
              onPressed: () => context.router.push(
                TripMapRoute(tripId: sync.remoteTripId!),
              ),
              icon: const Icon(Icons.map),
              label: const Text('Vedi su mappa'),
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
          title: 'Sync fallita',
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
            ? 'Serve un nuovo tentativo manuale'
            : 'Errore definitivo dopo $attemptText';
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

class _SensorList extends StatelessWidget {
  final AcquisitionCubitState state;

  const _SensorList({required this.state});

  @override
  Widget build(BuildContext context) {
    final profile = state.samplingProfile;
    final sensors = [
      _SensorRowData(
        icon: Icons.sensors,
        label: 'Accelerometro',
        value: '${profile.accelerometerHz} Hz',
        isActive: state.isTracking && profile.accelerometerHz > 0,
      ),
      _SensorRowData(
        icon: Icons.screen_rotation_alt,
        label: 'Giroscopio',
        value: '${profile.gyroscopeHz} Hz',
        isActive: state.isTracking && profile.gyroscopeHz > 0,
      ),
      _SensorRowData(
        icon: Icons.explore,
        label: 'Magnetometro',
        value: '${profile.magnetometerHz} Hz',
        isActive: state.isTracking && profile.magnetometerHz > 0,
      ),
      _SensorRowData(
        icon: Icons.gps_fixed,
        label: 'GPS',
        value: profile.gpsEnabled ? 'on' : 'off',
        isActive: state.isTracking && profile.gpsEnabled,
      ),
      _SensorRowData(
        icon: Icons.view_timeline,
        label: 'Finestre HAR',
        value: profile.harWindowEnabled ? 'RAM' : 'off',
        isActive: state.isTracking && profile.harWindowEnabled,
      ),
      _SensorRowData(
        icon: Icons.storage,
        label: 'SQLite',
        value: profile.persistGpsPoints || profile.persistSensorWindows
            ? 'write'
            : 'idle',
        isActive: state.isTracking &&
            (profile.persistGpsPoints || profile.persistSensorWindows),
      ),
    ];

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sensori reali',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: Dimensions.paddingSmall),
          for (final sensor in sensors) _SensorRow(sensor: sensor),
        ],
      ),
    );
  }
}

class _SensorRowData {
  final IconData icon;
  final String label;
  final String value;
  final bool isActive;

  const _SensorRowData({
    required this.icon,
    required this.label,
    required this.value,
    required this.isActive,
  });
}

class _SensorRow extends StatelessWidget {
  final _SensorRowData sensor;

  const _SensorRow({required this.sensor});

  @override
  Widget build(BuildContext context) {
    final color =
        sensor.isActive ? ColorPalette.success : ColorPalette.textSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Dimensions.paddingSmall),
      child: Row(
        children: [
          Icon(sensor.icon, color: color),
          const SizedBox(width: Dimensions.paddingSmall),
          Expanded(
            child: Text(
              sensor.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          Text(
            sensor.value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
          ),
        ],
      ),
    );
  }
}

class _LastTransition extends StatelessWidget {
  final AcquisitionCubitState state;

  const _LastTransition({required this.state});

  @override
  Widget build(BuildContext context) {
    final transition = state.snapshot.lastTransition;

    return _Panel(
      child: Row(
        children: [
          const Icon(Icons.timeline, color: ColorPalette.primary),
          const SizedBox(width: Dimensions.paddingSmall),
          Expanded(
            child: Text(
              transition == null
                  ? 'Nessuna transizione'
                  : '${transition.from.wireName} -> ${transition.to.wireName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveMetricList extends StatelessWidget {
  final AcquisitionCubitState state;

  const _LiveMetricList({required this.state});

  @override
  Widget build(BuildContext context) {
    final clusters = state.metricClusters;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.monitor_heart, color: ColorPalette.primary),
              const SizedBox(width: Dimensions.paddingSmall),
              Expanded(
                child: Text(
                  'Valori live',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Text(
                '${clusters.length}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: ColorPalette.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: Dimensions.paddingSmall),
          if (clusters.isEmpty)
            Text(
              state.isTracking ? 'In attesa dei sensori' : 'Premi Start',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: ColorPalette.textSecondary,
                  ),
            )
          else
            SizedBox(
              height: 220,
              child: Scrollbar(
                thumbVisibility: true,
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: clusters.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    return _MetricClusterRow(cluster: clusters[index]);
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MetricClusterRow extends StatelessWidget {
  final AcquisitionMetricCluster cluster;

  const _MetricClusterRow({required this.cluster});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Dimensions.paddingSmall),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              _formatTime(cluster.startedAt),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: ColorPalette.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'sigma ${cluster.sigmaAverage.toStringAsFixed(2)}'
                  ' (${cluster.sigmaMin.toStringAsFixed(2)}-'
                  '${cluster.sigmaMax.toStringAsFixed(2)})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  'vel ${cluster.speedKmhAverage.toStringAsFixed(1)} km/h'
                  ' (${cluster.speedKmhMin.toStringAsFixed(1)}-'
                  '${cluster.speedKmhMax.toStringAsFixed(1)})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: ColorPalette.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Dimensions.paddingSmall),
          Text(
            'n=${cluster.sampleCount}',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: ColorPalette.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final localTime = time.toLocal();
    return '${_twoDigits(localTime.hour)}:'
        '${_twoDigits(localTime.minute)}:'
        '${_twoDigits(localTime.second)}';
  }

  String _twoDigits(int value) {
    return value.toString().padLeft(2, '0');
  }
}

class _Panel extends StatelessWidget {
  final Widget child;

  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ColorPalette.surface,
      elevation: Dimensions.cardElevation,
      borderRadius: BorderRadius.circular(Dimensions.borderRadiusMedium),
      child: Padding(
        padding: const EdgeInsets.all(Dimensions.paddingMedium),
        child: child,
      ),
    );
  }
}
