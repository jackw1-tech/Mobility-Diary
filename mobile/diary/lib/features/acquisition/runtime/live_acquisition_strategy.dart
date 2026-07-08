import 'package:diary/network/dto/ingestion/ingestion_start_result_dto.dart';
import 'dart:async';

import 'package:diary/features/acquisition/data/acquisition_local_database.dart';
import 'package:diary/features/acquisition/domain/acquisition_domain.dart';
import 'package:diary/features/acquisition/domain/acquisition_strategy.dart';
import 'package:diary/features/acquisition/domain/sensor_matrix_blob.dart';
import 'package:diary/features/acquisition/runtime/acquisition_sensor_runtime.dart';
import 'package:diary/network/service/trip_ingestion_service.dart';
import 'package:diary/network/dto/ingestion/active_ingestion_dto.dart';
import 'package:diary/mappers/ingestion_mapper.dart';

import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

typedef HeartbeatTimerFactory = Timer Function(
  Duration duration,
  void Function(Timer timer) callback,
);

class LiveAcquisitionStrategy extends WidgetsBindingObserver
    implements AcquisitionStrategy {
  static const Duration _backgroundInertialStaleAfter = Duration(seconds: 12);
  static const String _resumeInertialStaleReason = 'resume_inertial_stale';

  final FsmConfig _config;
  final AcquisitionLocalDatabase _database;
  late final AcquisitionDao _dao;
  final Uuid _uuid;
  final String _deviceId;
  final Future<String> Function()? _deviceIdProvider;
  final AcquisitionSensorRuntime? _runtime;
  final bool _ownsRuntime;
  final TripIngestionService? _ingestionService;
  final Duration _heartbeatInterval;
  final HeartbeatTimerFactory _heartbeatTimerFactory;
  final bool _observesAppLifecycle;
  // Se, riprendendo una sessione aperta, l'ultimo dato registrato e' piu'
  // vecchio di questa soglia (es. telefono spento per ore), la sessione viene
  // considerata stantia: si chiude al momento dell'ultimo dato noto invece di
  // continuare a registrare come se il buco non fosse mai successo.
  final Duration _staleSessionThreshold;
  // Iniettabile per i test: senza, il controllo di staleness userebbe
  // DateTime.now() reale, rendendo i test dipendenti da quando vengono
  // eseguiti rispetto a timestamp fissi nei fixture.
  final DateTime Function() _now;
  final StreamController<AcquisitionSnapshot> _snapshotController =
      StreamController<AcquisitionSnapshot>.broadcast(sync: true);

  late AcquisitionFsm _fsm;
  AcquisitionSnapshot _currentSnapshot = AcquisitionSnapshot.idle();
  String? _currentSessionId;
  String? _pendingSyncSessionId;
  Timer? _heartbeatTimer;
  StreamSubscription<AppLifecycleState>? _lifecycleSubscription;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  final Set<String> _persistedSensorWindowKeys = {};
  DateTime? _latestMotionWindowAt;
  int? _currentRemoteIngestionId;
  String? _currentDeviceId;
  double? _latestLatitude;
  double? _latestLongitude;
  double? _latestAccuracyMeters;

  LiveAcquisitionStrategy({
    FsmConfig config = const FsmConfig(),
    AcquisitionLocalDatabase? database,
    Uuid? uuid,
    String deviceId = 'local_device',
    Future<String> Function()? deviceIdProvider,
    bool enableRuntime = true,
    AcquisitionSensorRuntime? runtime,
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
        _ingestionService = ingestionService,
        _heartbeatInterval = heartbeatInterval,
        _staleSessionThreshold = staleSessionThreshold,
        _now = now ?? DateTime.now,
        _heartbeatTimerFactory = heartbeatTimerFactory ??
            ((duration, callback) => Timer.periodic(
                  duration,
                  callback,
                )),
        _observesAppLifecycle = observeAppLifecycle && lifecycleEvents == null,
        _ownsRuntime = enableRuntime && runtime == null,
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
  AcquisitionSnapshot get currentSnapshot => _currentSnapshot;

  @override
  Future<void> start() async {
    await startTracking();
  }

  Future<void> startTracking() async {
    if (_currentSnapshot.isTracking) {
      return;
    }
    if (await _dao.latestUnclosedCoreSyncJob() != null) {
      throw const IngestionApiException('Richiesta ingestion fallita');
    }

    await _startNewTrackingSession(allowConflictRecovery: true);
  }

  Future<void> _startNewTrackingSession({
    required bool allowConflictRecovery,
  }) async {
    final now = DateTime.now().toUtc();
    final sessionId = _uuid.v4();
    final deviceId = await _resolveDeviceId();

    IngestionStartResultDto? remoteStart;
    try {
      remoteStart = await _ingestionService?.startIngestion(
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
      throw const IngestionApiException('Richiesta ingestion fallita');
    }

    _persistedSensorWindowKeys.clear();
    _latestMotionWindowAt = null;
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
  Future<AcquisitionStopResult> stop() async {
    return stopTracking();
  }

  Future<AcquisitionStopResult> stopTracking() async {
    await _runtime?.stop();
    _heartbeatTimer?.cancel();

    final sessionId = _currentSessionId;

    if (sessionId != null) {
      await _dao.endSession(
        id: sessionId,
        endedAt: DateTime.now().toUtc(),
      );
    }

    _currentSessionId = null;
    _currentRemoteIngestionId = null;
    _currentDeviceId = null;
    _persistedSensorWindowKeys.clear();
    _latestMotionWindowAt = null;
    _fsm = AcquisitionFsm(config: _config);
    _emit(AcquisitionSnapshot.idle());

    if (sessionId == null) {
      return const AcquisitionStopResult.none();
    }
    return AcquisitionStopResult.syncSession(sessionId);
  }

  @override
  Future<void> ingestEvent(TrackingEvent event) async {
    if (!_currentSnapshot.isTracking) {
      return;
    }

    if (event is MotionWindowEvaluated) {
      _latestMotionWindowAt = event.timestamp;
    }

    final decision = _fsm.apply(
      event,
      evidenceMode: _evidenceModeFor(event.timestamp),
    );
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

  Future<AcquisitionStopResult> resumeOrReconcile() async {
    await _resumeOpenTrackingSessionIfNeeded();
    await _reconcileRemoteActiveIngestion();
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
  Future<List<List<double>>> currentSensorWindow() async {
    final sessionId = _currentSessionId;
    if (sessionId == null || !_currentSnapshot.isTracking) {
      return const [];
    }
    final window = await _dao.latestSensorWindow(sessionId);
    if (window == null) return const [];
    return decodeSensorMatrixBlob(
      window.matrixBlob,
      sampleCount: window.sampleCount,
    );
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _lifecycleSubscription?.cancel();
    if (_observesAppLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
    }
    if (_ownsRuntime) {
      _runtime?.dispose();
    }
    _snapshotController.close();
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
      throw const IngestionApiException('Richiesta ingestion fallita');
    }

    final localSession = await _dao.findOpenSession(active.clientSessionId);
    if (localSession != null) {
      final resumed = await _resumeSession(
        localSession,
        remoteIngestionId: active.ingestionId,
      );
      if (!resumed) {
        // La sessione era stantia: e' stata chiusa e messa in coda di sync,
        // ma il backend continua a considerarla attiva finche' il suo core
        // non arriva (non possiamo abbandonarla: perderemmo i dati raccolti
        // prima del buco, il backend rifiuta il core di un'ingestion
        // abbandonata). L'utente deve attendere che quella sync completi,
        // come per qualunque altro sync pendente.
        throw const IngestionApiException('Richiesta ingestion fallita');
      }
      return true;
    }

    await _ingestionService?.abandonIngestion(
      ingestionId: active.ingestionId,
      deviceId: deviceId,
    );
    await _startNewTrackingSession(allowConflictRecovery: false);
    return true;
  }

  ActiveIngestionDto? _activeIngestionFromConflict(
      IngestionApiException error) {
    final active = error.body['active_ingestion'];
    if (active is Map<String, dynamic>) {
      return ActiveIngestionDto.fromJson(active);
    }
    if (active is Map) {
      return ActiveIngestionDto.fromJson(Map<String, dynamic>.from(active));
    }
    return null;
  }

  Future<void> _reconcileRemoteActiveIngestion() async {
    final api = _ingestionService;
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
    _lifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      unawaited(_sendHeartbeatIfTracking());
    }
  }

  FsmEvidenceMode _evidenceModeFor(DateTime timestamp) {
    if (_lifecycleState == AppLifecycleState.resumed ||
        !_isBackgroundInertialStale(timestamp)) {
      return FsmEvidenceMode.strictSensors;
    }
    return FsmEvidenceMode.forceStationary;
  }

  bool _isBackgroundInertialStale(DateTime timestamp) {
    final latestMotionWindowAt = _latestMotionWindowAt;
    return latestMotionWindowAt == null ||
        timestamp.difference(latestMotionWindowAt) >
            _backgroundInertialStaleAfter;
  }

  void _restartHeartbeat() {
    _heartbeatTimer?.cancel();
    if (_ingestionService == null ||
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
    final api = _ingestionService;
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

  /// Riprende una sessione locale ancora aperta. Ritorna `false` (senza
  /// riprendere la registrazione) se l'ultimo dato noto e' piu' vecchio di
  /// [_staleSessionThreshold] — es. il telefono si e' spento per ore: in tal
  /// caso la sessione viene chiusa al momento dell'ultimo dato registrato
  /// (non "ora", che includerebbe il buco) e messa in coda di sync, invece di
  /// continuare a registrare come se il buco non fosse mai successo.
  Future<bool> _resumeSession(
    AcquisitionSession session, {
    int? remoteIngestionId,
  }) async {
    var latestTransition = await _dao.latestTransitionForSession(session.id);
    final latestGpsPoint = await _dao.latestGpsPointForSession(session.id);
    final latestSensorWindow = await _dao.latestSensorWindow(session.id);

    final lastKnownAt = _latestKnownEventAt(
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
    );
    final trackingState = _trackingStateFromWire(latestTransition?.toState);
    final profile = SamplingProfile.forState(trackingState);
    final snapshotUpdatedAt = _latestKnownEventAt(
      session,
      latestTransition,
      latestGpsPoint,
      latestSensorWindow,
    );

    _persistedSensorWindowKeys.clear();
    _latestMotionWindowAt = null;
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
    _restartHeartbeat();
    return true;
  }

  DateTime _latestKnownEventAt(
    AcquisitionSession session,
    StateTransition? latestTransition,
    GpsPoint? latestGpsPoint,
    SensorWindow? latestSensorWindow,
  ) {
    var latest = session.startedAt;
    final transitionAt = latestTransition?.timestamp;
    if (transitionAt != null && transitionAt.isAfter(latest)) {
      latest = transitionAt;
    }
    final gpsAt = latestGpsPoint?.timestamp;
    if (gpsAt != null && gpsAt.isAfter(latest)) {
      latest = gpsAt;
    }
    final sensorAt = latestSensorWindow?.endTimestamp;
    if (sensorAt != null && sensorAt.isAfter(latest)) {
      latest = sensorAt;
    }
    return latest;
  }

  Future<StateTransition?> _correctStaleMovementOnResume({
    required AcquisitionSession session,
    required StateTransition? latestTransition,
    required SensorWindow? latestSensorWindow,
  }) async {
    if (_trackingStateFromWire(latestTransition?.toState) !=
        TrackingState.movement) {
      return latestTransition;
    }

    final inertialReferenceAt = _resumeInertialReferenceAt(
      session,
      latestTransition,
      latestSensorWindow,
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
      reason: _resumeInertialStaleReason,
      timestamp: correctedAt,
      sigma: latestTransition?.sigma ?? 0,
      speedMps: latestTransition?.speedMps ?? 0,
    );
    return _dao.latestTransitionForSession(session.id);
  }

  DateTime _resumeInertialReferenceAt(
    AcquisitionSession session,
    StateTransition? latestTransition,
    SensorWindow? latestSensorWindow,
  ) {
    var referenceAt = latestSensorWindow?.endTimestamp ?? session.startedAt;
    final transitionAt = latestTransition?.timestamp;
    if (transitionAt != null && transitionAt.isAfter(referenceAt)) {
      referenceAt = transitionAt;
    }
    return referenceAt;
  }

  /// Chiude localmente una sessione stantia al momento dell'ultimo dato noto
  /// (non "ora") e la mette in coda di sync — lo stesso percorso di uno stop
  /// esplicito, solo innescato automaticamente invece che dall'utente.
  Future<void> _closeStaleSession(
    String sessionId,
    DateTime lastKnownAt,
  ) async {
    await _dao.endSession(id: sessionId, endedAt: lastKnownAt);
    _pendingSyncSessionId = sessionId;
    _emit(AcquisitionSnapshot.idle());
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
      matrixBlob: encodeSensorMatrixBlob(modelInput),
    );
    _persistedSensorWindowKeys.add(windowKey);
  }

  String _sensorWindowKey(HarSensorWindow window) {
    return '${window.startedAt.microsecondsSinceEpoch}-'
        '${window.endedAt.microsecondsSinceEpoch}';
  }
}
