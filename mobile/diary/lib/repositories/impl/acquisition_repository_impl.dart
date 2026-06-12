import 'dart:async';
import 'dart:convert';

import 'package:diary/features/acquisition/data/acquisition_local_database.dart';
import 'package:diary/features/acquisition/domain/acquisition_domain.dart';
import 'package:diary/features/acquisition/runtime/acquisition_sensor_runtime.dart';
import 'package:diary/features/acquisition/sync/trip_sync_queue.dart';
import 'package:diary/repositories/acquisition_repository.dart';
import 'package:uuid/uuid.dart';

class AcquisitionRepositoryImpl implements AcquisitionRepository {
  final FsmConfig _config;
  final AcquisitionLocalDatabase _database;
  late final AcquisitionDao _dao;
  final Uuid _uuid;
  final String _deviceId;
  final AcquisitionSensorRuntime? _runtime;
  final TripSyncQueue? _syncQueue;
  final StreamController<AcquisitionSnapshot> _snapshotController =
      StreamController<AcquisitionSnapshot>.broadcast();

  late AcquisitionFsm _fsm;
  AcquisitionSnapshot _currentSnapshot = AcquisitionSnapshot.idle();
  AcquisitionSyncSnapshot _currentSyncSnapshot =
      const AcquisitionSyncSnapshot.none();
  String? _currentSessionId;
  Timer? _potentialMotionTimeoutTimer;
  Timer? _syncRetryTimer;
  final Set<String> _persistedSensorWindowKeys = {};

  AcquisitionRepositoryImpl({
    FsmConfig config = const FsmConfig(),
    AcquisitionLocalDatabase? database,
    Uuid? uuid,
    String deviceId = 'local_device',
    bool enableRuntime = true,
    AcquisitionSensorRuntime? runtime,
    TripSyncQueue? syncQueue,
  })  : _config = config,
        _database = database ?? AcquisitionLocalDatabase(),
        _uuid = uuid ?? const Uuid(),
        _deviceId = deviceId,
        _syncQueue = syncQueue,
        _runtime =
            enableRuntime ? runtime ?? AcquisitionSensorRuntime() : null {
    _dao = _database.acquisitionDao;
    _fsm = AcquisitionFsm(config: _config);
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

    _potentialMotionTimeoutTimer?.cancel();
    _persistedSensorWindowKeys.clear();
    final now = DateTime.now().toUtc();
    final sessionId = _uuid.v4();
    _fsm = AcquisitionFsm(config: _config);
    await _dao.createSession(
      id: sessionId,
      deviceId: _deviceId,
      startedAt: now,
    );
    _currentSessionId = sessionId;
    _emit(
      AcquisitionSnapshot(
        isTracking: true,
        trackingState: TrackingState.stationary,
        samplingProfile: const SamplingProfile.stationary(),
        latestSigma: 0,
        latestSpeedMetersPerSecond: 0,
        lastTransition: null,
        updatedAt: now,
      ),
    );
    await _runtime?.start(
      profile: const SamplingProfile.stationary(),
      onEvent: ingestEvent,
      onHarWindow: _persistHarWindowIfActive,
    );
  }

  @override
  Future<void> stopTracking() async {
    _potentialMotionTimeoutTimer?.cancel();
    _potentialMotionTimeoutTimer = null;
    await _runtime?.stop();
    final sessionId = _currentSessionId;
    if (sessionId != null) {
      await _dao.endSession(
        id: sessionId,
        endedAt: DateTime.now().toUtc(),
      );
    }

    _currentSessionId = null;
    _persistedSensorWindowKeys.clear();
    _fsm = AcquisitionFsm(config: _config);
    _emit(AcquisitionSnapshot.idle());

    // STOP non bloccante: si accoda un SyncJob persistente (insert locale veloce)
    // e si "kicka" la coda senza attendere la rete (REPORT D5).
    if (sessionId != null) {
      await _dao.createSyncJobIfAbsent(sessionId);
      unawaited(_syncQueue?.kick() ?? Future<void>.value());
    }
  }

  @override
  Future<void> ingestEvent(TrackingEvent event) async {
    if (!_currentSnapshot.isTracking) {
      return;
    }

    final decision = _fsm.apply(event);
    final transition = decision.transition;
    final sessionId = _currentSessionId;

    if (transition != null && sessionId != null) {
      await _dao.insertTransition(
        sessionId: sessionId,
        fromState: transition.from.wireName,
        toState: transition.to.wireName,
        reason: transition.reason,
        timestamp: transition.timestamp,
        sigma: _fsm.latestSigma,
        speedMps: _fsm.latestSpeedMetersPerSecond,
      );
    }

    _syncPotentialMotionTimeout(decision.state);

    if (event is GpsFixReceived &&
        event.latitude != null &&
        event.longitude != null &&
        sessionId != null &&
        decision.samplingProfile.persistGpsPoints) {
      await _dao.insertGpsPoint(
        sessionId: sessionId,
        latitude: event.latitude!,
        longitude: event.longitude!,
        timestamp: event.timestamp,
        speedMps: event.speedMetersPerSecond,
        accuracyMeters: event.accuracyMeters,
      );
    }

    await _persistCompletedHarWindowsIfNeeded(decision);

    _emit(
      AcquisitionSnapshot(
        isTracking: true,
        trackingState: decision.state,
        samplingProfile: decision.samplingProfile,
        latestSigma: _fsm.latestSigma,
        latestSpeedMetersPerSecond: _fsm.latestSpeedMetersPerSecond,
        lastTransition: decision.transition,
        updatedAt: event.timestamp,
      ),
    );
    await _runtime?.configure(decision.samplingProfile);
  }

  @override
  Future<void> resumeSync() async {
    await _syncQueue?.kick();
  }

  @override
  void dispose() {
    _potentialMotionTimeoutTimer?.cancel();
    _syncRetryTimer?.cancel();
    _runtime?.dispose();
    _snapshotController.close();
    _database.close();
  }

  void _syncPotentialMotionTimeout(TrackingState state) {
    if (state == TrackingState.potentialMotion &&
        _potentialMotionTimeoutTimer == null) {
      _potentialMotionTimeoutTimer = Timer(
        _config.potentialMotionTimeout,
        () => ingestEvent(
          PotentialMotionTimeoutElapsed(timestamp: DateTime.now().toUtc()),
        ),
      );
      return;
    }

    if (state != TrackingState.potentialMotion) {
      _potentialMotionTimeoutTimer?.cancel();
      _potentialMotionTimeoutTimer = null;
    }
  }

  void _emit(AcquisitionSnapshot snapshot) {
    _currentSnapshot = snapshot;
    if (!_snapshotController.isClosed) {
      _snapshotController.add(snapshot);
    }
  }

  void _scheduleSyncRetry(AcquisitionSyncSnapshot snapshot) {
    _syncRetryTimer?.cancel();

    final shouldPoll =
        snapshot.status == AcquisitionSyncStatus.waitingProcessing ||
            snapshot.status == AcquisitionSyncStatus.failedRetryable;
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
      status: _syncStatusFromWire(job.status),
      localSessionId: job.localSessionId,
      remoteIngestionId: job.remoteIngestionId,
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

  Future<void> _persistCompletedHarWindowsIfNeeded(
    FsmDecision decision,
  ) async {
    final runtime = _runtime;
    final sessionId = _currentSessionId;
    if (!decision.samplingProfile.persistSensorWindows ||
        runtime == null ||
        sessionId == null) {
      return;
    }

    for (final window in runtime.completedHarWindows.reversed) {
      await _persistHarWindow(sessionId: sessionId, window: window);
    }
  }

  Future<void> _persistHarWindowIfActive(HarSensorWindow window) async {
    final sessionId = _currentSessionId;
    if (sessionId == null ||
        !_currentSnapshot.samplingProfile.persistSensorWindows) {
      return;
    }

    await _persistHarWindow(sessionId: sessionId, window: window);
  }

  Future<void> _persistHarWindow({
    required String sessionId,
    required HarSensorWindow window,
  }) async {
    final windowKey = _sensorWindowKey(window);
    if (_persistedSensorWindowKeys.contains(windowKey)) {
      return;
    }

    final modelInput = window.modelInputMatrix;
    await _dao.insertSensorWindow(
      sessionId: sessionId,
      startTimestamp: window.startedAt,
      endTimestamp: window.endedAt,
      sampleCount: modelInput.length,
      frequencyHz: HarSensorWindow.targetSamplingHz,
      matrixJson: jsonEncode(modelInput),
    );
    _persistedSensorWindowKeys.add(windowKey);
  }

  String _sensorWindowKey(HarSensorWindow window) {
    return '${window.startedAt.microsecondsSinceEpoch}-'
        '${window.endedAt.microsecondsSinceEpoch}';
  }
}
