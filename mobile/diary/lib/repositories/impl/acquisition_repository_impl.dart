import 'dart:async';

import 'package:diary/network/service/impl/acquisition_local_database.dart';
import 'package:diary/model/entities/acquisition/acquisition_domain.dart';
import 'package:diary/repositories/acquisition_strategy.dart';
import 'package:diary/network/service/impl/acquisition_sensor_runtime.dart';
import 'package:diary/repositories/impl/acquisition/live_acquisition_strategy.dart'
    hide HeartbeatTimerFactory;
import 'package:diary/repositories/impl/acquisition/replay_acquisition_strategy.dart';
import 'package:diary/mappers/acquisition_mapper.dart';
import 'package:diary/mappers/upload_mapper.dart';
import 'package:diary/network/service/trip_upload_service.dart';
import 'package:diary/repositories/acquisition_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

typedef HeartbeatTimerFactory = Timer Function(
  Duration duration,
  void Function(Timer timer) callback,
);

class AcquisitionRepositoryImpl extends WidgetsBindingObserver
    implements AcquisitionRepository {
  final StreamController<AcquisitionSnapshot> _snapshotController =
      StreamController<AcquisitionSnapshot>.broadcast(sync: true);
  AcquisitionSnapshot _currentSnapshot = AcquisitionSnapshot.idle();

  @override
  Stream<AcquisitionSnapshot> get snapshots => _snapshotController.stream;

  @override
  AcquisitionSnapshot get currentSnapshot => _currentSnapshot;

  void emitSnapshot(AcquisitionSnapshot snapshot) {
    _currentSnapshot = snapshot;
    if (!_snapshotController.isClosed) {
      _snapshotController.add(snapshot);
    }
  }

  void closeSnapshots() => _snapshotController.close();

  final FsmConfig _config;
  final AcquisitionLocalDatabase _database;
  late final AcquisitionDao _dao;
  final Uuid _uuid;
  final String _deviceId;
  final Future<String> Function()? _deviceIdProvider;
  final bool _enableRuntime;
  final AcquisitionSensorRuntime? _runtime;
  final Future<void> Function()? _syncKick;
  final TripUploadService? _uploadService;
  final UploadMapper _mapper;
  final AcquisitionMapper _acquisitionMapper;
  final Duration _heartbeatInterval;
  final HeartbeatTimerFactory _heartbeatTimerFactory;
  final Duration _staleSessionThreshold;
  final DateTime Function() _now;
  final bool _observesAppLifecycle;

  AcquisitionStrategy? _activeAcquisitionStrategy;
  StreamSubscription<AppLifecycleState>? _lifecycleSubscription;
  Timer? _syncRetryTimer;
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
    Future<void> Function()? syncKick,
    TripUploadService? uploadService,
    UploadMapper? mapper,
    AcquisitionMapper? acquisitionMapper,
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
        _syncKick = syncKick,
        _uploadService = uploadService,
        _mapper = mapper ?? UploadMapper(),
        _acquisitionMapper = acquisitionMapper ?? AcquisitionMapper(),
        _heartbeatInterval = heartbeatInterval,
        _staleSessionThreshold = staleSessionThreshold,
        _now = now ?? DateTime.now,
        _heartbeatTimerFactory = heartbeatTimerFactory ??
            ((duration, callback) => Timer.periodic(duration, callback)),
        _observesAppLifecycle = observeAppLifecycle && lifecycleEvents == null {
    _dao = _database.acquisitionDao;
    _lifecycleSubscription = lifecycleEvents?.listen(_handleLifecycleState);
    if (_observesAppLifecycle) {
      WidgetsBinding.instance.addObserver(this);
    }
  }

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
  AcquisitionSyncSnapshot get currentSyncSnapshot => _currentSyncSnapshot;

  @override
  Future<void> startTracking() async {
    if (currentSnapshot.isTracking) {
      return;
    }
    await _ensureNoUnclosedCoreSyncJob();

    final strategy = _createLiveStrategy();
    _attachStrategy(strategy);
    try {
      await strategy.start();
      await _enqueuePendingLiveSyncIfNeeded(strategy);
    } catch (_) {
      await _disposeActiveStrategy();
      emitSnapshot(AcquisitionSnapshot.idle());
      rethrow;
    }
  }

  @override
  Future<void> startReplay(
    int sourceTripId, {
    DateTime? scheduledStartAt,
    double replaySpeedMultiplier = 1,
  }) async {
    if (currentSnapshot.isTracking) {
      return;
    }
    await _ensureNoUnclosedCoreSyncJob();

    final strategy = ReplayAcquisitionStrategy(
      sourceTripId: sourceTripId,
      onSnapshot: emitSnapshot,
      scheduledStartAt: scheduledStartAt,
      replaySpeedMultiplier: replaySpeedMultiplier,
      uploadService: _uploadService,
      mapper: _mapper,
      uuid: _uuid,
      deviceId: _deviceId,
      deviceIdProvider: _deviceIdProvider,
    );
    _attachStrategy(strategy);
    try {
      await strategy.start();
    } catch (_) {
      await _disposeActiveStrategy();
      emitSnapshot(AcquisitionSnapshot.idle());
      rethrow;
    }
  }

  @override
  Future<AcquisitionDiagnosticsReport?> stopTracking() async {
    final strategy = _activeAcquisitionStrategy;

    final result = await strategy!.stop();
    await _handleStopResult(result);
    await _disposeActiveStrategy();
    return result.diagnosticsReport;
  }

  @override
  Future<ReplayStopResult> stopReplay() async {
    final strategy = _activeAcquisitionStrategy;
    if (strategy == null || !currentSnapshot.isReplay) {
      throw const UploadApiException('Invalid state for stopReplay');
    }

    final result = await strategy.stop();
    await _handleStopResult(result);
    await _disposeActiveStrategy();

    final replayResult = result.replayResult;
    if (replayResult == null) {
      throw const UploadApiException('Invalid state for stopReplay');
    }
    return replayResult;
  }

  @override
  Future<void> ingestEvent(TrackingEvent event) async {
    final strategy = _activeAcquisitionStrategy;
    if (strategy == null) {
      return;
    }
    await strategy.ingestEvent(event);
  }

  // Funzione chiamata quando viene fatto l'autologin, controllo per prima cosa
  // se ci sono upload pendenti da completare
  @override
  Future<void> resumeSync() async {
    if (_activeAcquisitionStrategy == null) {
      final liveStrategy = _createLiveStrategy();
      _attachStrategy(liveStrategy);
      final result = await liveStrategy.resumeOrReconcile();
      await _handleStopResult(result);
      if (!currentSnapshot.isTracking) {
        await _disposeActiveStrategy();
      }
    } else if (_activeAcquisitionStrategy is LiveAcquisitionStrategy) {
      final liveStrategy =
          _activeAcquisitionStrategy! as LiveAcquisitionStrategy;
      final result = await liveStrategy.resumeOrReconcile();
      await _handleStopResult(result);
    }

    await _syncKick?.call();
  }

  @override
  Future<void> purgeLocalDataForRemoteTrip(int tripId) async {
    final sessionId = await _dao.localSessionIdForRemoteTrip(tripId);
    if (sessionId == null) {
      return;
    }
    await _dao.purgeSyncedSession(sessionId);
  }

  // Cerca la lista dei punti della sessione di tracking attuale
  @override
  Future<List<AcquisitionRoutePoint>> currentSessionRoute() async {
    final strategy = _activeAcquisitionStrategy;
    if (strategy == null) return const [];
    return strategy.currentSessionRoute();
  }

  @override
  Future<List<List<double>>> currentSensorWindow() async {
    final strategy = _activeAcquisitionStrategy;
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
    _activeAcquisitionStrategy?.dispose();
    closeSnapshots();
    _database.close();
  }

  // Funzione chiamata in automatico quando l'app cambia stato
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _handleLifecycleState(state);
  }

  LiveAcquisitionStrategy _createLiveStrategy() {
    return LiveAcquisitionStrategy(
      onSnapshot: emitSnapshot,
      config: _config,
      database: _database,
      uuid: _uuid,
      deviceId: _deviceId,
      deviceIdProvider: _deviceIdProvider,
      enableRuntime: _enableRuntime,
      runtime: _runtime,
      uploadService: _uploadService,
      mapper: _mapper,
      acquisitionMapper: _acquisitionMapper,
      heartbeatInterval: _heartbeatInterval,
      staleSessionThreshold: _staleSessionThreshold,
      now: _now,
      heartbeatTimerFactory: _heartbeatTimerFactory,
    );
  }

  void _attachStrategy(AcquisitionStrategy strategy) {
    _activeAcquisitionStrategy?.dispose();
    _activeAcquisitionStrategy = strategy;
  }

  Future<void> _disposeActiveStrategy() async {
    _activeAcquisitionStrategy?.dispose();
    _activeAcquisitionStrategy = null;
  }

  Future<void> _ensureNoUnclosedCoreSyncJob() async {
    if (await _dao.latestUnclosedCoreSyncJob() != null) {
      throw const UploadApiException('Richiesta upload fallita');
    }
  }

  //Funzione chiamata quando l'utente in modo naturale clicca stop
  Future<void> _handleStopResult(AcquisitionStopResult result) async {
    final syncSessionId = result.syncSessionId;
    if (syncSessionId == null) {
      return;
    }
    await _dao.createSyncJobIfAbsent(syncSessionId);
    _kickSync();
  }

  Future<void> _enqueuePendingLiveSyncIfNeeded(
    LiveAcquisitionStrategy strategy,
  ) async {
    final syncSessionId = strategy.takePendingSyncSessionId();
    if (syncSessionId != null) {
      await _handleStopResult(AcquisitionStopResult.syncSession(syncSessionId));
    }
  }

  // Inoltra il lifecycle alla sola strategia che ne ha bisogno e riattiva la
  // coda di sync quando l'app torna in primo piano.
  void _handleLifecycleState(AppLifecycleState state) {
    final strategy = _activeAcquisitionStrategy;
    if (strategy is LiveAcquisitionStrategy) {
      strategy.applyLifecycleState(state);
    }
    if (state == AppLifecycleState.resumed) {
      _kickSync();
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
    _syncRetryTimer = Timer(delay, _kickSync);
  }

  void _kickSync() {
    final kick = _syncKick;
    if (kick != null) unawaited(kick());
  }

  AcquisitionSyncSnapshot _syncSnapshotFromJob(SyncJob? job) =>
      _acquisitionMapper.mapSyncSnapshot(job);
}
