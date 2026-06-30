import 'dart:async';

import 'dart:async';
import 'dart:convert';

import 'package:diary/features/acquisition/data/acquisition_local_database.dart';
import 'package:diary/features/acquisition/domain/acquisition_domain.dart';
import 'package:diary/features/acquisition/runtime/acquisition_sensor_runtime.dart';
import 'package:diary/features/acquisition/sync/trip_ingestion_api.dart';
import 'package:diary/features/acquisition/sync/trip_package_builder.dart';
import 'package:diary/features/acquisition/sync/trip_sync_queue.dart';
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
  final AcquisitionSensorRuntime? _runtime;
  final TripSyncQueue? _syncQueue;
  final TripIngestionApi? _ingestionApi;
  final Duration _heartbeatInterval;
  final HeartbeatTimerFactory _heartbeatTimerFactory;
  final bool _observesAppLifecycle;
  final StreamController<AcquisitionSnapshot> _snapshotController =
      StreamController<AcquisitionSnapshot>.broadcast();

  late AcquisitionFsm _fsm;
  AcquisitionSnapshot _currentSnapshot = AcquisitionSnapshot.idle();
  AcquisitionSyncSnapshot _currentSyncSnapshot =
      const AcquisitionSyncSnapshot.none();
  String? _currentSessionId;
  Timer? _syncRetryTimer;
  Timer? _heartbeatTimer;
  StreamSubscription<AppLifecycleState>? _lifecycleSubscription;
  final Set<String> _persistedSensorWindowKeys = {};
  int? _currentRemoteIngestionId;
  String? _currentDeviceId;
  int? _replaySourceTripId;
  List<Map<String, dynamic>>? _replayPoints;
  List<Map<String, dynamic>>? _replayTransitions;
  double? _latestLatitude;
  double? _latestLongitude;
  double? _latestAccuracyMeters;
  Timer? _replayTimer;

  AcquisitionRepositoryImpl({
    FsmConfig config = const FsmConfig(),
    AcquisitionLocalDatabase? database,
    Uuid? uuid,
    String deviceId = 'local_device',
    Future<String> Function()? deviceIdProvider,
    bool enableRuntime = true,
    AcquisitionSensorRuntime? runtime,
    TripSyncQueue? syncQueue,
    TripIngestionApi? ingestionApi,
    Duration heartbeatInterval = const Duration(minutes: 5),
    HeartbeatTimerFactory? heartbeatTimerFactory,
    Stream<AppLifecycleState>? lifecycleEvents,
    bool observeAppLifecycle = false,
  })  : _config = config,
        _database = database ?? AcquisitionLocalDatabase(),
        _uuid = uuid ?? const Uuid(),
        _deviceId = deviceId,
        _deviceIdProvider = deviceIdProvider,
        _ingestionApi = ingestionApi,
        _syncQueue = syncQueue,
        _heartbeatInterval = heartbeatInterval,
        _heartbeatTimerFactory = heartbeatTimerFactory ??
            ((duration, callback) => Timer.periodic(
                  duration,
                  callback,
                )),
        _observesAppLifecycle = observeAppLifecycle && lifecycleEvents == null,
        _runtime =
            enableRuntime ? runtime ?? AcquisitionSensorRuntime() : null {
    _dao = _database.acquisitionDao;
    _fsm = AcquisitionFsm(config: _config);
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
    if (await _dao.latestUnclosedCoreSyncJob() != null) {
      throw const PendingTripSyncException();
    }

    await _startNewTrackingSession(allowConflictRecovery: true);
  }

  Future<void> _startNewTrackingSession({
    required bool allowConflictRecovery,
  }) async {
    final now = DateTime.now().toUtc();
    final sessionId = _uuid.v4();
    final deviceId = await _resolveDeviceId();

    IngestionStartResult? remoteStart;
    try {
      remoteStart = await _ingestionApi?.startIngestion(
        clientSessionId: sessionId,
        startedAt: now,
        deviceId: deviceId,
      );
    } on IngestionApiException catch (error) {
      if (allowConflictRecovery &&
          error.statusCode == 409 &&
          await _recoverFromStartConflict(error, deviceId)) {
        return;
      }
      throw const StartRequiresConnectionException();
    }

    _persistedSensorWindowKeys.clear();
    _latestLatitude = null;
    _latestLongitude = null;
    _latestAccuracyMeters = null;
    _fsm = AcquisitionFsm(config: _config);
    await _dao.createSession(
      id: sessionId,
      deviceId: deviceId,
      startedAt: now,
      remoteIngestionId: remoteStart?.ingestionId,
    );
    _currentSessionId = sessionId;
    _currentRemoteIngestionId = remoteStart?.ingestionId;
    _currentDeviceId = deviceId;
    _restartHeartbeat();
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
  Future<void> startReplay(int sourceTripId) async {
    if (_currentSnapshot.isTracking) {
      return;
    }
    if (await _dao.latestUnclosedCoreSyncJob() != null) {
      throw const PendingTripSyncException();
    }

    final now = DateTime.now().toUtc();
    final sessionId = _uuid.v4();
    final deviceId = await _resolveDeviceId();

    IngestionStartResult? remoteStart;
    try {
      remoteStart = await _ingestionApi?.startIngestion(
        clientSessionId: sessionId,
        startedAt: now,
        deviceId: deviceId,
        sourceTripId: sourceTripId,
      );
    } on IngestionApiException catch (error) {
      if (error.statusCode == 409) {
        throw const ActiveTripOnAnotherDeviceException();
      }
      throw const StartRequiresConnectionException();
    }

    final replayData = await _ingestionApi?.getReplayData(sourceTripId);
    if (replayData == null) {
      throw const StartRequiresConnectionException('Failed to load replay data');
    }

    _persistedSensorWindowKeys.clear();
    _latestLatitude = null;
    _latestLongitude = null;
    _latestAccuracyMeters = null;
    _fsm = AcquisitionFsm(config: _config);

    // Non crea sessione SQLite.
    _currentSessionId = sessionId;
    _currentRemoteIngestionId = remoteStart?.ingestionId;
    _currentDeviceId = deviceId;
    _replaySourceTripId = sourceTripId;
    _restartHeartbeat();
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

    _startReplayTimer(replayData);
  }

  void _startReplayTimer(Map<String, dynamic> data) {
    final rawPoints = data['points'] as List<dynamic>? ?? [];
    final rawTransitions = data['transitions'] as List<dynamic>? ?? [];

    if (rawPoints.isEmpty && rawTransitions.isEmpty) {
      stopTracking();
      return;
    }

    DateTime pTime(dynamic p) => DateTime.parse(p['timestamp'] as String).toUtc();
    
    _replayPoints = List<Map<String, dynamic>>.from(rawPoints)
      ..sort((a, b) => pTime(a).compareTo(pTime(b)));
    _replayTransitions = List<Map<String, dynamic>>.from(rawTransitions)
      ..sort((a, b) => pTime(a).compareTo(pTime(b)));

    final points = _replayPoints!;
    final transitions = _replayTransitions!;

    final firstPoint = points.isNotEmpty ? pTime(points.first) : null;
    final firstTransition = transitions.isNotEmpty ? pTime(transitions.first) : null;
    final lastPoint = points.isNotEmpty ? pTime(points.last) : null;
    final lastTransition = transitions.isNotEmpty ? pTime(transitions.last) : null;

    DateTime? startTime;
    if (firstPoint != null && firstTransition != null) {
      startTime = firstPoint.isBefore(firstTransition) ? firstPoint : firstTransition;
    } else {
      startTime = firstPoint ?? firstTransition;
    }

    DateTime? endTime;
    if (lastPoint != null && lastTransition != null) {
      endTime = lastPoint.isAfter(lastTransition) ? lastPoint : lastTransition;
    } else {
      endTime = lastPoint ?? lastTransition;
    }

    if (startTime == null || endTime == null) {
      stopTracking();
      return;
    }

    final startReplayAt = DateTime.now();
    int nextPointIdx = 0;
    int nextTransitionIdx = 0;
    FsmTransition? lastFsmTransition;

    _replayTimer?.cancel();
    _replayTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final elapsed = DateTime.now().difference(startReplayAt);
      final currentReplayTime = startTime!.add(elapsed);

      bool updated = false;

      while (nextTransitionIdx < transitions.length &&
          !pTime(transitions[nextTransitionIdx]).isAfter(currentReplayTime)) {
        final t = transitions[nextTransitionIdx];
        final nextState = _trackingStateFromWire(t['to_state'] as String);
        _fsm.forceState(nextState, (t['sigma'] as num).toDouble(), (t['speed_mps'] as num).toDouble());
        lastFsmTransition = FsmTransition(
          from: _trackingStateFromWire(t['from_state'] as String),
          to: nextState,
          reason: t['reason'] as String? ?? 'replay',
          timestamp: pTime(t),
        );
        nextTransitionIdx++;
        updated = true;
      }

      while (nextPointIdx < points.length &&
          !pTime(points[nextPointIdx]).isAfter(currentReplayTime)) {
        final p = points[nextPointIdx];
        _latestLatitude = (p['latitude'] as num).toDouble();
        _latestLongitude = (p['longitude'] as num).toDouble();
        _latestAccuracyMeters = (p['accuracy_meters'] as num).toDouble();
        nextPointIdx++;
        updated = true;
      }

      final remainingSeconds = endTime!.difference(currentReplayTime).inSeconds;
      int? replaySecondsRemaining;
      if (remainingSeconds <= 15) {
        replaySecondsRemaining = remainingSeconds > 0 ? remainingSeconds : 0;
      }

      if (updated || remainingSeconds <= 15) {
        _emit(AcquisitionSnapshot(
          isTracking: true,
          trackingState: _fsm.currentState ?? TrackingState.stationary,
          samplingProfile: SamplingProfile.forState(_fsm.currentState ?? TrackingState.stationary),
          latestSigma: _fsm.latestSigma,
          latestSpeedMetersPerSecond: _fsm.latestSpeedMetersPerSecond,
          lastTransition: lastFsmTransition,
          updatedAt: currentReplayTime,
          latitude: _latestLatitude,
          longitude: _latestLongitude,
          accuracyMeters: _latestAccuracyMeters,
          replaySecondsRemaining: replaySecondsRemaining,
        ));
      }

      if (remainingSeconds <= 0) {
        _replayTimer?.cancel();
      }
    });
  }

  @override
  Future<void> stopTracking() async {
    await _runtime?.stop();
    _heartbeatTimer?.cancel();
    _replayTimer?.cancel();
    
    final sessionId = _currentSessionId;
    final isReplay = _replaySourceTripId != null;
    
    if (sessionId != null && !isReplay) {
      await _dao.endSession(
        id: sessionId,
        endedAt: DateTime.now().toUtc(),
      );
    }

    _currentSessionId = null;
    _currentRemoteIngestionId = null;
    _currentDeviceId = null;
    _replaySourceTripId = null;
    _persistedSensorWindowKeys.clear();
    _fsm = AcquisitionFsm(config: _config);
    _emit(AcquisitionSnapshot.idle());
    
    await _endSessionAndQueueSync(sessionId, isReplay);
  }

  @override
  Future<ReplayStopResult> stopReplay() async {
    final cutoffTimestamp = _currentSnapshot.updatedAt;
    _replayTimer?.cancel();
    _heartbeatTimer?.cancel();

    if (_replaySourceTripId == null || _currentSessionId == null) {
      throw const StartRequiresConnectionException('Invalid state for stopReplay');
    }

    DateTime pTime(dynamic p) => DateTime.parse(p['timestamp'] as String).toUtc();

    final filteredPoints = _replayPoints!
        .where((p) => !pTime(p).isAfter(cutoffTimestamp))
        .toList();
    final filteredTransitions = _replayTransitions!
        .where((t) => !pTime(t).isAfter(cutoffTimestamp))
        .toList();

    final now = DateTime.now().toUtc();
    final shift = now.difference(cutoffTimestamp);

    String shiftIso(DateTime original) {
      return _utcIso(original.add(shift));
    }

    final shiftedPoints = filteredPoints.map((p) {
      return {
        ...p,
        'timestamp': shiftIso(pTime(p)),
      };
    }).toList();

    final shiftedTransitions = filteredTransitions.map((t) {
      return {
        ...t,
        'timestamp': shiftIso(pTime(t)),
      };
    }).toList();

    final firstShiftedTs = shiftedPoints.isNotEmpty
        ? DateTime.parse(shiftedPoints.first['timestamp'] as String).toUtc()
        : (shiftedTransitions.isNotEmpty
            ? DateTime.parse(shiftedTransitions.first['timestamp'] as String).toUtc()
            : now);

    final payload = {
      'app_version': '',
      'client_session_id': _currentSessionId,
      'device_id': _currentDeviceId ?? '',
      'device_platform': '',
      'ended_at': shiftIso(now),
      'cutoff_source_timestamp': _utcIso(cutoffTimestamp),
      'expected_raw_parts': const {},
      'gps_points': shiftedPoints,
      if (_currentRemoteIngestionId != null) 'ingestion_id': _currentRemoteIngestionId,
      'schema_version': 1,
      'started_at': shiftIso(firstShiftedTs),
      'state_transitions': shiftedTransitions,
      'timezone': '',
    };

    final corePayload = TripCorePayload(payload);
    final response = await _ingestionApi?.postCoreInline(body: corePayload.requestBody);

    if (response == null) {
      throw const StartRequiresConnectionException('Network error during stopReplay');
    }

    _currentSessionId = null;
    _currentRemoteIngestionId = null;
    _currentDeviceId = null;
    _replaySourceTripId = null;
    _replayPoints = null;
    _replayTransitions = null;

    _emit(AcquisitionSnapshot.idle());

    return ReplayStopResult(tripId: response.tripId);
  }

  String _utcIso(DateTime value) {
    final utc = value.toUtc();
    final year = utc.year.toString().padLeft(4, '0');
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    final hour = utc.hour.toString().padLeft(2, '0');
    final minute = utc.minute.toString().padLeft(2, '0');
    final second = utc.second.toString().padLeft(2, '0');
    final fractionMicros = utc.millisecond * 1000 + utc.microsecond;
    final base = '$year-$month-${day}T$hour:$minute:$second';
    if (fractionMicros == 0) return '${base}Z';
    return '$base.${fractionMicros.toString().padLeft(6, '0')}Z';
  }

  Future<void> _endSessionAndQueueSync(String? sessionId, bool isReplay) async {
    // STOP non bloccante: si accoda un SyncJob persistente (insert locale veloce)
    // e si "kicka" la coda senza attendere la rete (REPORT D5).
    if (sessionId != null && !isReplay) {
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

    if (event is GpsFixReceived &&
        event.latitude != null &&
        event.longitude != null) {
      _latestLatitude = event.latitude;
      _latestLongitude = event.longitude;
      _latestAccuracyMeters = event.accuracyMeters;

      if (sessionId != null && decision.samplingProfile.persistGpsPoints) {
        await _dao.insertGpsPoint(
          sessionId: sessionId,
          latitude: event.latitude!,
          longitude: event.longitude!,
          timestamp: event.timestamp,
          speedMps: event.speedMetersPerSecond,
          accuracyMeters: event.accuracyMeters,
        );
      }
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
        latitude: _latestLatitude,
        longitude: _latestLongitude,
        accuracyMeters: _latestAccuracyMeters,
      ),
    );
    await _runtime?.configure(decision.samplingProfile);
  }

  @override
  Future<void> resumeSync() async {
    await _resumeOpenTrackingSessionIfNeeded();
    await _reconcileRemoteActiveIngestion();
    await _syncQueue?.kick();
  }

  @override
  Future<List<AcquisitionRoutePoint>> currentSessionRoute() async {
    final sessionId = _currentSessionId;
    if (sessionId == null || !_currentSnapshot.isTracking) {
      return const [];
    }
    final points = await _dao.gpsPointsForSession(sessionId);
    return [
      for (final point in points)
        AcquisitionRoutePoint(point.latitude, point.longitude),
    ];
  }

  @override
  void dispose() {
    _syncRetryTimer?.cancel();
    _heartbeatTimer?.cancel();
    _replayTimer?.cancel();
    _lifecycleSubscription?.cancel();
    if (_observesAppLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _runtime?.dispose();
    _snapshotController.close();
    _database.close();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _handleLifecycleState(state);
  }

  void _emit(AcquisitionSnapshot snapshot) {
    _currentSnapshot = snapshot;
    if (!_snapshotController.isClosed) {
      _snapshotController.add(snapshot);
    }
  }

  Future<String> _resolveDeviceId() async {
    final provider = _deviceIdProvider;
    if (provider == null) {
      return _deviceId;
    }
    return provider();
  }

  Future<bool> _recoverFromStartConflict(
    IngestionApiException error,
    String deviceId,
  ) async {
    final active = _activeIngestionFromConflict(error);
    if (active == null) {
      return false;
    }
    if (active.deviceId != deviceId) {
      throw const ActiveTripOnAnotherDeviceException();
    }

    final localSession = await _dao.findOpenSession(active.clientSessionId);
    if (localSession != null) {
      await _resumeSession(localSession, remoteIngestionId: active.ingestionId);
      return true;
    }

    await _ingestionApi?.abandonIngestion(
      ingestionId: active.ingestionId,
      deviceId: deviceId,
    );
    await _startNewTrackingSession(allowConflictRecovery: false);
    return true;
  }

  ActiveIngestion? _activeIngestionFromConflict(IngestionApiException error) {
    final active = error.body['active_ingestion'];
    if (active is Map<String, dynamic>) {
      return ActiveIngestion.fromJson(active);
    }
    if (active is Map) {
      return ActiveIngestion.fromJson(Map<String, dynamic>.from(active));
    }
    return null;
  }

  Future<void> _reconcileRemoteActiveIngestion() async {
    final api = _ingestionApi;
    if (api == null || _currentSnapshot.isTracking) {
      return;
    }

    try {
      final active = await api.getActiveIngestion();
      if (active == null) {
        return;
      }

      final deviceId = await _resolveDeviceId();
      if (active.deviceId != deviceId) {
        return;
      }

      final localSession = await _dao.findOpenSession(active.clientSessionId);
      if (localSession != null) {
        await _resumeSession(localSession,
            remoteIngestionId: active.ingestionId);
        return;
      }

      // Una sessione fermata offline ha ``endedAt`` valorizzato (quindi non e'
      // "open") ma puo' avere ancora un core sync pendente: il backend la vede
      // attiva perche' ``recording_closed_at`` viene scritto solo all'arrivo del
      // core. Non dobbiamo abbandonarla, altrimenti la sync successiva fallirebbe
      // con "viaggio abbandonato" e il viaggio andrebbe perso.
      if (await _hasPendingCoreSync(active.clientSessionId)) {
        return;
      }

      await api.abandonIngestion(
        ingestionId: active.ingestionId,
        deviceId: deviceId,
      );
    } on IngestionApiException {
      // La riconciliazione all'avvio non deve bloccare la UI o la sync locale.
    }
  }

  Future<bool> _hasPendingCoreSync(String localSessionId) async {
    final job = await _dao.syncJobForSession(localSessionId);
    if (job == null) {
      return false;
    }
    return syncJobActiveStatuses.contains(job.coreStatus);
  }

  void _handleLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_sendHeartbeatIfTracking());
    }
  }

  void _restartHeartbeat() {
    _heartbeatTimer?.cancel();
    if (_ingestionApi == null ||
        _currentRemoteIngestionId == null ||
        _currentSessionId == null ||
        _currentDeviceId == null) {
      return;
    }
    _heartbeatTimer = _heartbeatTimerFactory(_heartbeatInterval, (_) {
      unawaited(_sendHeartbeatIfTracking());
    });
  }

  Future<void> _sendHeartbeatIfTracking() async {
    final api = _ingestionApi;
    final ingestionId = _currentRemoteIngestionId;
    final clientSessionId = _currentSessionId;
    final deviceId = _currentDeviceId;
    if (!_currentSnapshot.isTracking ||
        api == null ||
        ingestionId == null ||
        clientSessionId == null ||
        deviceId == null) {
      return;
    }

    try {
      await api.heartbeatIngestion(
        ingestionId: ingestionId,
        clientSessionId: clientSessionId,
        deviceId: deviceId,
      );
    } catch (_) {
      // Heartbeat best-effort: non deve mai fermare i sensori locali.
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

  Future<void> _resumeOpenTrackingSessionIfNeeded() async {
    if (_currentSnapshot.isTracking) {
      return;
    }

    final session = await _dao.latestOpenSession();
    if (session == null) {
      return;
    }

    await _resumeSession(session);
  }

  Future<void> _resumeSession(
    AcquisitionSession session, {
    int? remoteIngestionId,
  }) async {
    final latestTransition = await _dao.latestTransitionForSession(session.id);
    final latestGpsPoint = await _dao.latestGpsPointForSession(session.id);
    final trackingState = _trackingStateFromWire(
      latestTransition?.toState,
    );
    final profile = SamplingProfile.forState(trackingState);

    _persistedSensorWindowKeys.clear();
    _currentSessionId = session.id;
    _currentRemoteIngestionId = remoteIngestionId ?? session.remoteIngestionId;
    _currentDeviceId = session.deviceId;
    _fsm = AcquisitionFsm(config: _config, initialState: trackingState);
    _latestLatitude = latestGpsPoint?.latitude;
    _latestLongitude = latestGpsPoint?.longitude;
    _latestAccuracyMeters = latestGpsPoint?.accuracyMeters;

    _emit(
      AcquisitionSnapshot(
        isTracking: true,
        trackingState: trackingState,
        samplingProfile: profile,
        latestSigma: latestTransition?.sigma ?? 0,
        latestSpeedMetersPerSecond:
            latestGpsPoint?.speedMps ?? latestTransition?.speedMps ?? 0,
        lastTransition: latestTransition == null
            ? null
            : FsmTransition(
                from: _trackingStateFromWire(latestTransition.fromState),
                to: trackingState,
                reason: latestTransition.reason,
                timestamp: latestTransition.timestamp,
              ),
        updatedAt: latestGpsPoint?.timestamp ??
            latestTransition?.timestamp ??
            session.startedAt,
        latitude: _latestLatitude,
        longitude: _latestLongitude,
        accuracyMeters: _latestAccuracyMeters,
      ),
    );

    await _runtime?.start(
      profile: profile,
      onEvent: ingestEvent,
      onHarWindow: _persistHarWindowIfActive,
    );
    _restartHeartbeat();
  }

  TrackingState _trackingStateFromWire(String? wireName) {
    switch (wireName) {
      case 'MOVEMENT':
        return TrackingState.movement;
      case 'STATIONARY':
      default:
        return TrackingState.stationary;
    }
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
