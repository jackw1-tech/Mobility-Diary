import 'dart:async';

import 'package:diary/features/acquisition/data/acquisition_local_database.dart';
import 'package:diary/features/acquisition/domain/acquisition_domain.dart';
import 'package:diary/features/acquisition/runtime/acquisition_sensor_runtime.dart';
import 'package:diary/repositories/acquisition_repository.dart';
import 'package:uuid/uuid.dart';

class AcquisitionRepositoryImpl implements AcquisitionRepository {
  final FsmConfig _config;
  final AcquisitionLocalDatabase _database;
  late final AcquisitionDao _dao;
  final Uuid _uuid;
  final String _deviceId;
  final AcquisitionSensorRuntime? _runtime;
  final StreamController<AcquisitionSnapshot> _snapshotController =
      StreamController<AcquisitionSnapshot>.broadcast();

  late AcquisitionFsm _fsm;
  AcquisitionSnapshot _currentSnapshot = AcquisitionSnapshot.idle();
  String? _currentSessionId;
  Timer? _potentialMotionTimeoutTimer;

  AcquisitionRepositoryImpl({
    FsmConfig config = const FsmConfig(),
    AcquisitionLocalDatabase? database,
    Uuid? uuid,
    String deviceId = 'local_device',
    bool enableRuntime = true,
    AcquisitionSensorRuntime? runtime,
  })  : _config = config,
        _database = database ?? AcquisitionLocalDatabase(),
        _uuid = uuid ?? const Uuid(),
        _deviceId = deviceId,
        _runtime =
            enableRuntime ? runtime ?? AcquisitionSensorRuntime() : null {
    _dao = _database.acquisitionDao;
    _fsm = AcquisitionFsm(config: _config);
  }

  @override
  Stream<AcquisitionSnapshot> get snapshots => _snapshotController.stream;

  @override
  AcquisitionSnapshot get currentSnapshot => _currentSnapshot;

  @override
  Future<void> startTracking() async {
    if (_currentSnapshot.isTracking) {
      return;
    }

    _potentialMotionTimeoutTimer?.cancel();
    final now = DateTime.now();
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
        endedAt: DateTime.now(),
      );
    }

    _currentSessionId = null;
    _fsm = AcquisitionFsm(config: _config);
    _emit(AcquisitionSnapshot.idle());
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
  void dispose() {
    _potentialMotionTimeoutTimer?.cancel();
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
          PotentialMotionTimeoutElapsed(timestamp: DateTime.now()),
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
}
