import 'dart:async';

import 'package:diary/network/service/impl/acquisition_local_database.dart';
import 'package:diary/model/entities/acquisition/acquisition_domain.dart';
import 'package:diary/repositories/acquisition_strategy.dart';
import 'package:diary/network/service/impl/acquisition_sensor_runtime.dart';
import 'package:diary/repositories/impl/acquisition/live_acquisition_strategy.dart'
    hide HeartbeatTimerFactory;
import 'package:diary/repositories/impl/acquisition/replay_acquisition_strategy.dart';
import 'package:diary/repositories/trip_sync_queue.dart';
import 'package:diary/mappers/ingestion_mapper.dart';
import 'package:diary/network/service/trip_ingestion_service.dart';
import 'package:diary/repositories/acquisition_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

typedef HeartbeatTimerFactory = Timer Function(
  Duration duration,
  void Function(Timer timer) callback,
);

class AcquisitionRepositoryImpl extends WidgetsBindingObserver
    implements AcquisitionRepository {
  final FsmConfig _config;
  final AcquisitionLocalDatabase _database;
  late final AcquisitionDao _dao;
  final Uuid _uuid;
  final String _deviceId;
  final Future<String> Function()? _deviceIdProvider;
  final bool _enableRuntime;
  final AcquisitionSensorRuntime? _runtime;
  final TripSyncQueue? _syncQueue;
  final TripIngestionService? _ingestionService;
  final Duration _heartbeatInterval;
  final HeartbeatTimerFactory _heartbeatTimerFactory;
  final Duration _staleSessionThreshold;
  final DateTime Function() _now;
  final Stream<AppLifecycleState>? _lifecycleEvents;
  final bool _observesAppLifecycle;

  final StreamController<AcquisitionSnapshot> _snapshotController =
      StreamController<AcquisitionSnapshot>.broadcast(sync: true);

  AcquisitionStrategy? _activeStrategy;
  StreamSubscription<AcquisitionSnapshot>? _activeStrategySubscription;
  StreamSubscription<AppLifecycleState>? _lifecycleSubscription;
  Timer? _syncRetryTimer;
  AcquisitionSnapshot _currentSnapshot = AcquisitionSnapshot.idle();
  AcquisitionSyncSnapshot _currentSyncSnapshot =
      const AcquisitionSyncSnapshot.none();

  AcquisitionRepositoryImpl({
    FsmConfig config = const FsmConfig(),
    AcquisitionLocalDatabase? database,
    Uuid? uuid,
    String deviceId = 'local_device',
    Future<String> Function()? deviceIdProvider,
    bool enableRuntime = true,
    AcquisitionSensorRuntime? runtime,
    TripSyncQueue? syncQueue,
    TripIngestionService? ingestionService,
    IngestionMapper? mapper,
    Duration heartbeatInterval = const Duration(minutes: 5),
    Duration staleSessionThreshold = const Duration(minutes: 30),
    DateTime Function()? now,
    HeartbeatTimerFactory? heartbeatTimerFactory,
    Stream<AppLifecycleState>? lifecycleEvents,
    bool observeAppLifecycle = false,
  })  : _config = config,
        _database = database ?? AcquisitionLocalDatabase(),
        _uuid = uuid ?? const Uuid(),
        _deviceId = deviceId,
        _deviceIdProvider = deviceIdProvider,
        _enableRuntime = enableRuntime,
        _runtime = runtime,
        _syncQueue = syncQueue,
        _ingestionService = ingestionService,
        _heartbeatInterval = heartbeatInterval,
        _staleSessionThreshold = staleSessionThreshold,
        _now = now ?? DateTime.now,
        _heartbeatTimerFactory = heartbeatTimerFactory ??
            ((duration, callback) => Timer.periodic(duration, callback)),
        _lifecycleEvents = lifecycleEvents,
        _observesAppLifecycle = observeAppLifecycle && lifecycleEvents == null {
    _dao = _database.acquisitionDao;
    _lifecycleSubscription = lifecycleEvents?.listen(_handleLifecycleState);
    if (_observesAppLifecycle) {
      WidgetsBinding.instance.addObserver(this);
    }
  }

  @override
  Stream<AcquisitionSnapshot> get snapshots => _snapshotController.stream;

  @override
  Stream<AcquisitionSyncSnapshot> get syncSnapshots {
    return _dao.watchLatestSyncJob().map((job) {
      final snapshot = _syncSnapshotFromJob(job);
      _currentSyncSnapshot = snapshot;
      _scheduleSyncRetry(snapshot);
      return snapshot;
    });
  }

  @override
  AcquisitionSnapshot get currentSnapshot => _currentSnapshot;

  @override
  AcquisitionSyncSnapshot get currentSyncSnapshot => _currentSyncSnapshot;

  @override
  Future<void> startTracking() async {
    if (_currentSnapshot.isTracking) {
      return;
    }
    await _ensureNoUnclosedCoreSyncJob();

    final strategy = _createLiveStrategy();
    _attachStrategy(strategy);
    try {
      await strategy.start();
      _emit(strategy.currentSnapshot);
      await _enqueuePendingLiveSyncIfNeeded(strategy);
    } catch (_) {
      await _disposeActiveStrategy();
      _emit(AcquisitionSnapshot.idle());
      rethrow;
    }
  }

  @override
  Future<void> startReplay(
    int sourceTripId, {
    DateTime? scheduledStartAt,
    double replaySpeedMultiplier = 1,
  }) async {
    if (_currentSnapshot.isTracking) {
      return;
    }
    await _ensureNoUnclosedCoreSyncJob();

    final strategy = ReplayAcquisitionStrategy(
      sourceTripId: sourceTripId,
      scheduledStartAt: scheduledStartAt,
      replaySpeedMultiplier: replaySpeedMultiplier,
      ingestionService: _ingestionService,
      uuid: _uuid,
      deviceId: _deviceId,
      deviceIdProvider: _deviceIdProvider,
    );
    _attachStrategy(strategy);
    try {
      await strategy.start();
      _emit(strategy.currentSnapshot);
    } catch (_) {
      await _disposeActiveStrategy();
      _emit(AcquisitionSnapshot.idle());
      rethrow;
    }
  }

  @override
  Future<void> stopTracking() async {
    final strategy = _activeStrategy;
    if (strategy == null) {
      _emit(AcquisitionSnapshot.idle());
      return;
    }

    final result = await strategy.stop();
    _emit(strategy.currentSnapshot);
    await _handleStopResult(result);
    await _disposeActiveStrategy();
  }

  @override
  Future<ReplayStopResult> stopReplay() async {
    final strategy = _activeStrategy;
    if (strategy == null || !_currentSnapshot.isReplay) {
      throw const IngestionApiException('Invalid state for stopReplay');
    }

    final result = await strategy.stop();
    _emit(strategy.currentSnapshot);
    await _handleStopResult(result);
    await _disposeActiveStrategy();

    final replayResult = result.replayResult;
    if (replayResult == null) {
      throw const IngestionApiException('Invalid state for stopReplay');
    }
    return replayResult;
  }

  @override
  Future<void> ingestEvent(TrackingEvent event) async {
    final strategy = _activeStrategy;
    if (strategy == null) {
      return;
    }
    await strategy.ingestEvent(event);
    _emit(strategy.currentSnapshot);
  }

  @override
  Future<void> resumeSync() async {
    if (_activeStrategy == null) {
      final liveStrategy = _createLiveStrategy();
      _attachStrategy(liveStrategy);
      final result = await liveStrategy.resumeOrReconcile();
      await _handleStopResult(result);
      if (liveStrategy.currentSnapshot.isTracking) {
        _emit(liveStrategy.currentSnapshot);
      } else {
        await _disposeActiveStrategy();
        _emit(AcquisitionSnapshot.idle());
      }
    } else if (_activeStrategy is LiveAcquisitionStrategy) {
      final liveStrategy = _activeStrategy! as LiveAcquisitionStrategy;
      final result = await liveStrategy.resumeOrReconcile();
      await _handleStopResult(result);
      _emit(liveStrategy.currentSnapshot);
    }

    await _syncQueue?.kick();
  }

  @override
  Future<void> purgeLocalDataForRemoteTrip(int tripId) async {
    final sessionId = await _dao.localSessionIdForRemoteTrip(tripId);
    if (sessionId == null) {
      return;
    }
    await _dao.purgeSyncedSession(sessionId);
  }

  @override
  Future<List<AcquisitionRoutePoint>> currentSessionRoute() async {
    final strategy = _activeStrategy;
    if (strategy == null) return const [];
    return strategy.currentSessionRoute();
  }

  @override
  Future<List<List<double>>> currentSensorWindow() async {
    final strategy = _activeStrategy;
    if (strategy == null) return const [];
    return strategy.currentSensorWindow();
  }

  @override
  void dispose() {
    _syncRetryTimer?.cancel();
    _lifecycleSubscription?.cancel();
    if (_observesAppLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _activeStrategySubscription?.cancel();
    _activeStrategy?.dispose();
    _snapshotController.close();
    _database.close();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _handleLifecycleState(state);
  }

  LiveAcquisitionStrategy _createLiveStrategy() {
    return LiveAcquisitionStrategy(
      config: _config,
      database: _database,
      uuid: _uuid,
      deviceId: _deviceId,
      deviceIdProvider: _deviceIdProvider,
      enableRuntime: _enableRuntime,
      runtime: _runtime,
      ingestionService: _ingestionService,
      heartbeatInterval: _heartbeatInterval,
      staleSessionThreshold: _staleSessionThreshold,
      now: _now,
      heartbeatTimerFactory: _heartbeatTimerFactory,
      lifecycleEvents: _lifecycleEvents,
      observeAppLifecycle: false,
    );
  }

  void _attachStrategy(AcquisitionStrategy strategy) {
    _activeStrategySubscription?.cancel();
    _activeStrategy?.dispose();
    _activeStrategy = strategy;
    _activeStrategySubscription = strategy.snapshots.listen(_emit);
  }

  Future<void> _disposeActiveStrategy() async {
    await _activeStrategySubscription?.cancel();
    _activeStrategySubscription = null;
    _activeStrategy?.dispose();
    _activeStrategy = null;
  }

  Future<void> _ensureNoUnclosedCoreSyncJob() async {
    if (await _dao.latestUnclosedCoreSyncJob() != null) {
      throw const IngestionApiException('Richiesta ingestion fallita');
    }
  }

  Future<void> _handleStopResult(AcquisitionStopResult result) async {
    final syncSessionId = result.syncSessionId;
    if (syncSessionId == null) {
      return;
    }
    await _dao.createSyncJobIfAbsent(syncSessionId);
    unawaited(_syncQueue?.kick() ?? Future<void>.value());
  }

  Future<void> _enqueuePendingLiveSyncIfNeeded(
    LiveAcquisitionStrategy strategy,
  ) async {
    final syncSessionId = strategy.takePendingSyncSessionId();
    if (syncSessionId != null) {
      await _handleStopResult(AcquisitionStopResult.syncSession(syncSessionId));
    }
  }

  void _emit(AcquisitionSnapshot snapshot) {
    _currentSnapshot = snapshot;
    if (!_snapshotController.isClosed) {
      _snapshotController.add(snapshot);
    }
  }

  void _handleLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncQueue?.kick() ?? Future<void>.value());
    }
  }

  void _scheduleSyncRetry(AcquisitionSyncSnapshot snapshot) {
    _syncRetryTimer?.cancel();

    final shouldPoll =
        snapshot.status == AcquisitionSyncStatus.waitingProcessing ||
            snapshot.status == AcquisitionSyncStatus.failedRetryable ||
            snapshot.rawStatus == AcquisitionSyncStatus.failedRetryable;
    final nextRetryAt = snapshot.nextRetryAt;
    if (!shouldPoll || nextRetryAt == null) {
      return;
    }

    final now = DateTime.now().toUtc();
    final delay =
        nextRetryAt.isAfter(now) ? nextRetryAt.difference(now) : Duration.zero;
    _syncRetryTimer = Timer(delay, () {
      unawaited(_syncQueue?.kick() ?? Future<void>.value());
    });
  }

  AcquisitionSyncSnapshot _syncSnapshotFromJob(SyncJob? job) {
    if (job == null) {
      return const AcquisitionSyncSnapshot.none();
    }

    return AcquisitionSyncSnapshot(
      status: _syncStatusFromWire(job.coreStatus),
      rawStatus: _syncStatusFromWire(job.rawStatus),
      localSessionId: job.localSessionId,
      remoteIngestionId: job.remoteIngestionId,
      remoteTripId: job.remoteTripId,
      coreMapAvailable: job.coreMapAvailable,
      attempts: job.attempts,
      nextRetryAt: job.nextRetryAt,
      lastError: job.lastError,
      updatedAt: job.updatedAt,
    );
  }

  AcquisitionSyncStatus _syncStatusFromWire(String status) {
    switch (status) {
      case syncJobPending:
        return AcquisitionSyncStatus.pending;
      case syncJobPackaging:
        return AcquisitionSyncStatus.packaging;
      case syncJobUploading:
        return AcquisitionSyncStatus.uploading;
      case syncJobWaitingProcessing:
        return AcquisitionSyncStatus.waitingProcessing;
      case syncJobCompleted:
        return AcquisitionSyncStatus.completed;
      case syncJobFailedRetryable:
        return AcquisitionSyncStatus.failedRetryable;
      case syncJobFailedFinal:
        return AcquisitionSyncStatus.failedFinal;
    }

    return AcquisitionSyncStatus.none;
  }
}
