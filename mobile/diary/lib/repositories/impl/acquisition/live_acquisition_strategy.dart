import 'dart:async';

import 'package:diary/network/service/impl/acquisition_local_database.dart';
import 'package:diary/model/entities/acquisition/acquisition_domain.dart';
import 'package:diary/model/entities/acquisition/upload_models.dart';
import 'package:diary/repositories/acquisition_repository.dart';
import 'package:diary/repositories/acquisition_strategy.dart';
import 'package:diary/model/entities/acquisition/sensor_matrix_json.dart';
import 'package:diary/network/service/impl/acquisition_sensor_runtime.dart';
import 'package:diary/network/service/trip_upload_service.dart';
import 'package:diary/mappers/upload_mapper.dart';
import 'package:diary/mappers/acquisition_mapper.dart';
import 'package:diary/repositories/impl/acquisition/har_window_recorder.dart';
import 'package:diary/repositories/impl/acquisition/fsm_diagnostics_recorder.dart';
import 'package:diary/repositories/impl/acquisition/upload_heartbeat.dart';

import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

export 'package:diary/repositories/impl/acquisition/upload_heartbeat.dart'
    show HeartbeatTimerFactory;

class LiveAcquisitionStrategy implements AcquisitionStrategy {
  static const Duration _backgroundInertialStaleAfter = Duration(seconds: 15);

  final FsmConfig _config;
  final AcquisitionLocalDatabase _database;
  late final AcquisitionDao _dao;
  final Uuid _uuid;
  final String _deviceId;
  final Future<String> Function()? _deviceIdProvider;
  final AcquisitionSensorRuntime? _runtime;
  final bool _ownsRuntime;
  final TripUploadService? _uploadService;
  final UploadMapper _mapper;
  final AcquisitionMapper _acquisitionMapper;
  final AcquisitionSnapshotListener onSnapshot;
  late final UploadHeartbeat _heartbeat;
  late final HarWindowRecorder _harWindows;
  final FsmDiagnosticsRecorder _diagnosticsRecorder;
  final Duration _staleSessionThreshold;
  final DateTime Function() _now;

  AcquisitionSnapshot _currentSnapshot = AcquisitionSnapshot.idle();
  bool _acceptSnapshots = true;

  AcquisitionSnapshot get currentSnapshot => _currentSnapshot;

  void emitSnapshot(AcquisitionSnapshot snapshot) {
    if (!_acceptSnapshots) {
      return;
    }
    _currentSnapshot = snapshot;
    onSnapshot(snapshot);
  }

  void closeSnapshotEmission() => _acceptSnapshots = false;

  late AcquisitionFsm _fsm;
  String? _currentSessionId;
  String? _pendingSyncSessionId;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  DateTime? _latestMotionWindowAt;
  int? _currentRemoteUploadId;
  String? _currentDeviceId;
  double? _latestLatitude;
  double? _latestLongitude;
  double? _latestAccuracyMeters;

  LiveAcquisitionStrategy({
    required this.onSnapshot,
    FsmConfig config = const FsmConfig(),
    AcquisitionLocalDatabase? database,
    Uuid? uuid,
    String deviceId = 'local_device',
    Future<String> Function()? deviceIdProvider,
    bool enableRuntime = true,
    AcquisitionSensorRuntime? runtime,
    TripUploadService? uploadService,
    UploadMapper? mapper,
    AcquisitionMapper? acquisitionMapper,
    Duration heartbeatInterval = const Duration(minutes: 5),
    Duration staleSessionThreshold = const Duration(minutes: 30),
    DateTime Function()? now,
    HeartbeatTimerFactory? heartbeatTimerFactory,
    FsmDiagnosticsRecorder? diagnosticsRecorder,
  })  : _config = config,
        _database = database ?? AcquisitionLocalDatabase(),
        _uuid = uuid ?? const Uuid(),
        _deviceId = deviceId,
        _deviceIdProvider = deviceIdProvider,
        _uploadService = uploadService,
        _mapper = mapper ?? UploadMapper(),
        _acquisitionMapper = acquisitionMapper ?? AcquisitionMapper(),
        _staleSessionThreshold = staleSessionThreshold,
        _now = now ?? DateTime.now,
        _diagnosticsRecorder = diagnosticsRecorder ?? FsmDiagnosticsRecorder(),
        _ownsRuntime = enableRuntime && runtime == null,
        _runtime =
            enableRuntime ? runtime ?? AcquisitionSensorRuntime() : null {
    _dao = _database.acquisitionDao;
    _fsm = AcquisitionFsm(config: _config);
    _harWindows = HarWindowRecorder(_dao);
    _heartbeat = UploadHeartbeat(
      service: uploadService,
      interval: heartbeatInterval,
      timerFactory: heartbeatTimerFactory ??
          ((duration, callback) => Timer.periodic(duration, callback)),
      target: _heartbeatTarget,
      isTracking: () => currentSnapshot.isTracking,
    );
  }

  HeartbeatTarget? _heartbeatTarget() {
    final uploadId = _currentRemoteUploadId;
    final clientSessionId = _currentSessionId;
    final deviceId = _currentDeviceId;
    if (uploadId == null || clientSessionId == null || deviceId == null) {
      return null;
    }
    return HeartbeatTarget(
      uploadId: uploadId,
      clientSessionId: clientSessionId,
      deviceId: deviceId,
    );
  }

  @override
  Future<void> start() async {
    await startTracking();
  }

  Future<void> startTracking() async {
    if (currentSnapshot.isTracking) {
      return;
    }
    final runtime = _runtime;
    if (runtime != null && !await runtime.hasAcquisitionLocationPermission()) {
      throw const AcquisitionPermissionException();
    }
    if (await _dao.latestUnclosedCoreSyncJob() != null) {
      throw const UploadApiException('Richiesta upload fallita');
    }

    await _startNewTrackingSession(allowConflictRecovery: true);
  }

  Future<void> _startNewTrackingSession({
    required bool allowConflictRecovery,
  }) async {
    final now = DateTime.now().toUtc();
    final sessionId = _uuid.v4();
    final deviceId = await _resolveDeviceId();

    UploadStartResult? remoteStart;
    try {
      final startDto = await _uploadService?.startUpload(
        clientSessionId: sessionId,
        startedAt: now,
        deviceId: deviceId,
      );
      remoteStart =
          startDto == null ? null : _mapper.mapUploadStartResult(startDto);
    } on UploadApiException catch (error) {
      if (allowConflictRecovery &&
          error.statusCode == 409 &&
          await _recoverFromStartConflict(error, deviceId)) {
        return;
      }
      throw const UploadApiException('Richiesta upload fallita');
    }

    _harWindows.reset();
    _latestMotionWindowAt = null;
    _latestLatitude = null;
    _latestLongitude = null;
    _latestAccuracyMeters = null;
    _fsm = AcquisitionFsm(config: _config);
    await _dao.createSession(
      id: sessionId,
      deviceId: deviceId,
      startedAt: now,
      remoteUploadId: remoteStart?.uploadId,
    );
    _currentSessionId = sessionId;
    _currentRemoteUploadId = remoteStart?.uploadId;
    _currentDeviceId = deviceId;
    await _diagnosticsRecorder.start(
      sessionId: sessionId,
      startedAt: now,
    );
    _heartbeat.restart();
    emitSnapshot(
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
  Future<AcquisitionStopResult> stop() async {
    return stopTracking();
  }

  Future<AcquisitionStopResult> stopTracking() async {
    await _runtime?.stop();
    _heartbeat.cancel();

    final sessionId = _currentSessionId;
    final endedAt = _now().toUtc();

    if (sessionId != null) {
      await _dao.endSession(
        id: sessionId,
        endedAt: endedAt,
      );
    }
    final diagnosticsReport = sessionId == null
        ? null
        : await _diagnosticsRecorder.finish(endedAt: endedAt);

    _currentSessionId = null;
    _currentRemoteUploadId = null;
    _currentDeviceId = null;
    _harWindows.reset();
    _latestMotionWindowAt = null;
    _fsm = AcquisitionFsm(config: _config);
    emitSnapshot(AcquisitionSnapshot.idle());

    if (sessionId == null) {
      return const AcquisitionStopResult.none();
    }
    return AcquisitionStopResult.syncSession(
      sessionId,
      diagnosticsReport: diagnosticsReport,
    );
  }

  //Intercetto i nuovi dati dai sensoi / gps, richiamo la FSM e salvo i dati nel db
  @override
  Future<void> ingestEvent(TrackingEvent event) async {
    if (!currentSnapshot.isTracking) {
      return;
    }

    if (event is MotionWindowEvaluated) {
      _latestMotionWindowAt = event.timestamp;
    }

    final decision = _fsm.apply(
      event,
      evidenceMode: _evidenceModeFor(event.timestamp),
    );
    _diagnosticsRecorder.record(
      event: event,
      decision: decision,
      config: _config,
    );
    final transition = decision.transition;
    final sessionId = _currentSessionId;

    if (transition != null && sessionId != null) {
      // Inserisco nel db la transizione di stato
      await _dao.insertTransition(
        sessionId: sessionId,
        fromState: transition.from.wireName,
        toState: transition.to.wireName,
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

      // Inerisco nel db i dati del gps
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

    emitSnapshot(
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
    await _runtime?.configure(
      decision.samplingProfile,
      allowGpsRestart: _lifecycleState == AppLifecycleState.resumed,
    );
  }

  Future<AcquisitionStopResult> resumeOrReconcile() async {
    await _resumeOpenTrackingSessionIfNeeded();
    await _reconcileRemoteActiveUpload();
    final syncSessionId = takePendingSyncSessionId();
    if (syncSessionId == null) {
      return const AcquisitionStopResult.none();
    }
    return AcquisitionStopResult.syncSession(syncSessionId);
  }

  String? takePendingSyncSessionId() {
    final sessionId = _pendingSyncSessionId;
    _pendingSyncSessionId = null;
    return sessionId;
  }

  //Controlla se nel db ci sono punti gps
  @override
  Future<List<AcquisitionRoutePoint>> currentSessionRoute() async {
    final sessionId = _currentSessionId;
    if (sessionId == null || !currentSnapshot.isTracking) {
      return const [];
    }
    final points = await _dao.gpsPointsForSession(sessionId);
    return [
      for (final point in points)
        AcquisitionRoutePoint(point.latitude, point.longitude),
    ];
  }

  @override
  Future<List<List<double>>> currentSensorWindow() async {
    final sessionId = _currentSessionId;
    if (sessionId == null || !currentSnapshot.isTracking) {
      return const [];
    }
    final window = await _dao.latestSensorWindow(sessionId);
    if (window == null) return const [];
    return decodeSensorMatrixJson(window.matrixJson);
  }

  @override
  void dispose() {
    closeSnapshotEmission();
    _heartbeat.cancel();
    _diagnosticsRecorder.dispose();
    if (_ownsRuntime) {
      _runtime?.dispose();
    }
  }

  void applyLifecycleState(AppLifecycleState state) {
    _applyLifecycleState(state);
  }

  Future<String> _resolveDeviceId() async {
    final provider = _deviceIdProvider;
    if (provider == null) {
      return _deviceId;
    }
    return provider();
  }

  Future<bool> _recoverFromStartConflict(
    UploadApiException error,
    String deviceId,
  ) async {
    final active = _activeUploadFromConflict(error);
    if (active == null) {
      return false;
    }
    if (active.deviceId != deviceId) {
      throw const UploadApiException('Richiesta upload fallita');
    }

    final localSession = await _dao.findOpenSession(active.clientSessionId);
    if (localSession != null) {
      final resumed = await _resumeSession(
        localSession,
        remoteUploadId: active.uploadId,
      );
      if (!resumed) {
        // La sessione era stantia: e' stata chiusa e messa in coda di sync,
        // ma il backend continua a considerarla attiva finche' il suo core
        // non arriva (non possiamo abbandonarla: perderemmo i dati raccolti
        // prima del buco, il backend rifiuta il core di un'upload
        // abbandonata). L'utente deve attendere che quella sync completi,
        // come per qualunque altro sync pendente.
        throw const UploadApiException('Richiesta upload fallita');
      }
      return true;
    }

    await _uploadService?.abandonUpload(
      uploadId: active.uploadId,
      deviceId: deviceId,
    );
    await _startNewTrackingSession(allowConflictRecovery: false);
    return true;
  }

  ActiveUpload? _activeUploadFromConflict(UploadApiException error) {
    final dto = activeUploadFromConflict(error);
    return dto == null ? null : _mapper.mapActiveUpload(dto);
  }

  Future<void> _reconcileRemoteActiveUpload() async {
    final api = _uploadService;
    if (api == null || currentSnapshot.isTracking) {
      return;
    }

    try {
      final activeDto = await api.getActiveUpload();
      if (activeDto == null) {
        return;
      }
      final active = _mapper.mapActiveUpload(activeDto);

      final deviceId = await _resolveDeviceId();
      if (active.deviceId != deviceId) {
        return;
      }

      final localSession = await _dao.findOpenSession(active.clientSessionId);
      if (localSession != null) {
        await _resumeSession(localSession, remoteUploadId: active.uploadId);
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

      await api.abandonUpload(
        uploadId: active.uploadId,
        deviceId: deviceId,
      );
    } on UploadApiException {
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

  void _applyLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;

    if (state == AppLifecycleState.resumed) {
      //manda l heartbeat e aggiorna il last seen del trip
      unawaited(_heartbeat.send());
      unawaited(_runtime?.applyPendingGpsRestart() ?? Future<void>.value());
    }
  }

  // Se non arrivano dati dall'accellerometro da più di 15 secondi (app in background), la decisione la prendo guardando il gps
  FsmEvidenceMode _evidenceModeFor(DateTime timestamp) {
    if (_lifecycleState == AppLifecycleState.resumed ||
        !_isBackgroundInertialStale(timestamp)) {
      return FsmEvidenceMode.inertialAndGps;
    }
    return FsmEvidenceMode.gpsOnly;
  }

  bool _isBackgroundInertialStale(DateTime timestamp) {
    final latestMotionWindowAt = _latestMotionWindowAt;
    return latestMotionWindowAt == null ||
        timestamp.difference(latestMotionWindowAt) >
            _backgroundInertialStaleAfter;
  }

  Future<void> _resumeOpenTrackingSessionIfNeeded() async {
    if (currentSnapshot.isTracking) {
      return;
    }

    final session = await _dao.latestOpenSession();
    if (session == null) {
      return;
    }

    await _resumeSession(session);
  }

  Future<bool> _resumeSession(
    AcquisitionSession session, {
    int? remoteUploadId,
  }) async {
    var latestTransition = await _dao.latestTransitionForSession(session.id);
    final latestGpsPoint = await _dao.latestGpsPointForSession(session.id);
    final latestSensorWindow = await _dao.latestSensorWindow(session.id);

    final lastKnownAt = _acquisitionMapper.latestKnownEventAt(
      session,
      latestTransition,
      latestGpsPoint,
      latestSensorWindow,
    );
    if (_now().toUtc().difference(lastKnownAt) >= _staleSessionThreshold) {
      await _closeStaleSession(session.id, lastKnownAt);
      return false;
    }

    latestTransition = await _correctStaleMovementOnResume(
      session: session,
      latestTransition: latestTransition,
      latestSensorWindow: latestSensorWindow,
      latestGpsPoint: latestGpsPoint,
    );
    final trackingState = TrackingState.fromWire(latestTransition?.toState);
    final profile = SamplingProfile.forState(trackingState);
    final snapshotUpdatedAt = _acquisitionMapper.latestKnownEventAt(
      session,
      latestTransition,
      latestGpsPoint,
      latestSensorWindow,
    );

    _harWindows.reset();
    _latestMotionWindowAt = null;
    _currentSessionId = session.id;
    _currentRemoteUploadId = remoteUploadId ?? session.remoteUploadId;
    _currentDeviceId = session.deviceId;
    _fsm = AcquisitionFsm(config: _config, initialState: trackingState);
    _latestLatitude = latestGpsPoint?.latitude;
    _latestLongitude = latestGpsPoint?.longitude;
    _latestAccuracyMeters = latestGpsPoint?.accuracyMeters;
    await _diagnosticsRecorder.start(
      sessionId: session.id,
      startedAt: session.startedAt,
      append: true,
    );

    emitSnapshot(
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
                from: TrackingState.fromWire(latestTransition.fromState),
                to: trackingState,
                timestamp: latestTransition.timestamp,
              ),
        updatedAt: snapshotUpdatedAt,
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
    _heartbeat.restart();
    return true;
  }

  Future<StateTransition?> _correctStaleMovementOnResume({
    required AcquisitionSession session,
    required StateTransition? latestTransition,
    required SensorWindow? latestSensorWindow,
    required GpsPoint? latestGpsPoint,
  }) async {
    if (TrackingState.fromWire(latestTransition?.toState) !=
        TrackingState.movement) {
      return latestTransition;
    }

    final inertialReferenceAt = _acquisitionMapper.resumeInertialReferenceAt(
      session,
      latestTransition,
      latestSensorWindow,
      latestGpsPoint,
    );
    final correctedAt = inertialReferenceAt.add(_backgroundInertialStaleAfter);
    final now = _now().toUtc();
    if (!correctedAt.isBefore(now)) {
      return latestTransition;
    }

    await _dao.insertTransition(
      sessionId: session.id,
      fromState: TrackingState.movement.wireName,
      toState: TrackingState.stationary.wireName,
      timestamp: correctedAt,
      sigma: latestTransition?.sigma ?? 0,
      speedMps: latestTransition?.speedMps ?? 0,
    );
    return _dao.latestTransitionForSession(session.id);
  }

  Future<void> _closeStaleSession(
    String sessionId,
    DateTime lastKnownAt,
  ) async {
    await _dao.endSession(id: sessionId, endedAt: lastKnownAt);
    _pendingSyncSessionId = sessionId;
    emitSnapshot(AcquisitionSnapshot.idle());
  }

  Future<void> _persistHarWindowIfActive(HarSensorWindow window) async {
    final sessionId = _currentSessionId;
    if (sessionId == null ||
        !currentSnapshot.samplingProfile.persistSensorWindows) {
      return;
    }

    await _harWindows.persist(sessionId: sessionId, window: window);
  }
}
