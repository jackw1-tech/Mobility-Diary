import 'dart:async';

import 'package:diary/mappers/upload_mapper.dart';
import 'package:diary/model/entities/acquisition/acquisition_domain.dart';
import 'package:diary/model/entities/acquisition/upload_models.dart';
import 'package:diary/repositories/acquisition_strategy.dart';
import 'package:diary/repositories/impl/acquisition/trip_package_builder.dart';
import 'package:diary/network/service/trip_upload_service.dart';
import 'package:diary/repositories/impl/acquisition/acquisition_snapshot_emitter.dart';
import 'package:uuid/uuid.dart';

typedef ReplayTimerFactory = Timer Function(
  Duration duration,
  void Function(Timer timer) callback,
);

class ReplayAcquisitionStrategy
    with AcquisitionSnapshotEmitter
    implements AcquisitionStrategy {
  /// Motivo mostrato per le transizioni rigiocate: il backend restituisce solo
  /// from_state/to_state, non il motivo della decisione originale.
  static const String _replayTransitionReason = 'replay';

  final TripUploadService? _uploadService;
  final UploadMapper _mapper;
  final Uuid _uuid;
  final String _deviceId;
  final Future<String> Function()? _deviceIdProvider;
  final int _sourceTripId;
  final DateTime? _scheduledStartAt;
  final double _requestedReplaySpeedMultiplier;
  final ReplayTimerFactory _timerFactory;

  Timer? _replayTimer;
  String? _currentSessionId;
  int? _currentRemoteUploadId;
  String? _currentDeviceId;
  DateTime? _replayStartWallClock;
  double _replaySpeed = 1;
  List<CoreGpsPoint>? _replayPoints;
  List<CoreStateTransition>? _replayTransitions;
  double? _latestLatitude;
  double? _latestLongitude;
  double? _latestAccuracyMeters;

  ReplayAcquisitionStrategy({
    required int sourceTripId,
    DateTime? scheduledStartAt,
    double replaySpeedMultiplier = 1,
    TripUploadService? uploadService,
    UploadMapper? mapper,
    Uuid? uuid,
    String deviceId = 'local_device',
    Future<String> Function()? deviceIdProvider,
    ReplayTimerFactory? timerFactory,
  })  : _sourceTripId = sourceTripId,
        _scheduledStartAt = scheduledStartAt?.toUtc(),
        _requestedReplaySpeedMultiplier = replaySpeedMultiplier,
        _uploadService = uploadService,
        _mapper = mapper ?? UploadMapper(),
        _uuid = uuid ?? const Uuid(),
        _deviceId = deviceId,
        _deviceIdProvider = deviceIdProvider,
        _timerFactory = timerFactory ??
            ((duration, callback) => Timer.periodic(duration, callback));

  @override
  Future<void> start() async {
    if (currentSnapshot.isTracking) {
      return;
    }

    final now = DateTime.now().toUtc();
    final sessionId = _uuid.v4();
    final deviceId = await _resolveDeviceId();

    UploadStartResult? remoteStart;
    try {
      final startDto = await _uploadService?.startUpload(
        clientSessionId: sessionId,
        startedAt: now,
        deviceId: deviceId,
        sourceTripId: _sourceTripId,
      );
      remoteStart =
          startDto == null ? null : _mapper.mapUploadStartResult(startDto);
    } on UploadApiException {
      throw const UploadApiException('Richiesta upload fallita');
    }

    final replayDataDto =
        await _uploadService?.getReplayData(_sourceTripId);
    if (replayDataDto == null) {
      throw const UploadApiException('Richiesta upload fallita');
    }
    final replaySource = _mapper.mapReplayData(replayDataDto);

    _currentSessionId = sessionId;
    _currentRemoteUploadId = remoteStart?.uploadId;
    _currentDeviceId = deviceId;
    _latestLatitude = null;
    _latestLongitude = null;
    _latestAccuracyMeters = null;

    emitSnapshot(
      AcquisitionSnapshot(
        isTracking: true,
        trackingState: TrackingState.stationary,
        samplingProfile: const SamplingProfile.stationary(),
        latestSigma: 0,
        latestSpeedMetersPerSecond: 0,
        lastTransition: null,
        updatedAt: now,
        isReplay: true,
      ),
    );

    _startReplayTimer(
      replaySource,
      speedMultiplier: _replaySpeedMultiplier(_requestedReplaySpeedMultiplier),
    );
  }

  @override
  Future<AcquisitionStopResult> stop() async {
    final result = await _stopReplay();
    return AcquisitionStopResult.replay(result);
  }

  @override
  Future<void> ingestEvent(TrackingEvent event) async {
    // Replay is driven only by backend replay evidence and its timer.
  }

  @override
  Future<List<AcquisitionRoutePoint>> currentSessionRoute() async {
    return const [];
  }

  @override
  Future<List<List<double>>> currentSensorWindow() async {
    final offset = _currentReplayOffsetSeconds();
    if (offset == null) return const [];
    try {
      return await _uploadService?.getReplaySensorWindow(
            _sourceTripId,
            offset,
          ) ??
          const [];
    } on UploadApiException {
      return const [];
    }
  }

  @override
  void dispose() {
    _replayTimer?.cancel();
    closeSnapshots();
  }

  double _replaySpeedMultiplier(double value) {
    return value == 2 || value == 5 ? value : 1;
  }

  void _startReplayTimer(
    ReplaySource source, {
    required double speedMultiplier,
  }) {
    if (source.isEmpty) {
      emitSnapshot(AcquisitionSnapshot.idle());
      return;
    }

    _replayPoints = source.points;
    _replayTransitions = source.transitions;

    final points = source.points;
    final transitions = source.transitions;

    final firstPoint = points.isNotEmpty ? points.first.timestamp : null;
    final firstTransition =
        transitions.isNotEmpty ? transitions.first.timestamp : null;
    final lastPoint = points.isNotEmpty ? points.last.timestamp : null;
    final lastTransition =
        transitions.isNotEmpty ? transitions.last.timestamp : null;
    final startTime = _earlier(firstPoint, firstTransition);
    final endTime = _later(lastPoint, lastTransition);

    if (startTime == null || endTime == null) {
      emitSnapshot(AcquisitionSnapshot.idle());
      return;
    }

    emitSnapshot(
      AcquisitionSnapshot(
        isTracking: true,
        trackingState: TrackingState.stationary,
        samplingProfile: const SamplingProfile.stationary(),
        latestSigma: 0,
        latestSpeedMetersPerSecond: 0,
        lastTransition: null,
        updatedAt: startTime,
        replaySecondsRemaining: _replaySecondsRemaining(
          endTime.difference(startTime),
          speedMultiplier,
        ),
        isReplay: true,
      ),
    );

    final startReplayAt = DateTime.now();
    _replayStartWallClock = startReplayAt;
    _replaySpeed = speedMultiplier;
    int nextPointIdx = 0;
    int nextTransitionIdx = 0;
    TrackingState currentState = TrackingState.stationary;
    FsmTransition? lastFsmTransition;
    double latestSpeedMps = 0;

    _replayTimer?.cancel();
    _replayTimer = _timerFactory(const Duration(seconds: 1), (timer) {
      final elapsed = DateTime.now().difference(startReplayAt);
      final acceleratedReplayTime = startTime.add(
        Duration(
          microseconds: (elapsed.inMicroseconds * speedMultiplier).round(),
        ),
      );
      final currentReplayTime = acceleratedReplayTime.isAfter(endTime)
          ? endTime
          : acceleratedReplayTime;

      bool updated = false;

      while (nextTransitionIdx < transitions.length &&
          !transitions[nextTransitionIdx]
              .timestamp
              .isAfter(currentReplayTime)) {
        final t = transitions[nextTransitionIdx];
        final nextState = TrackingState.fromWire(t.toState);
        lastFsmTransition = FsmTransition(
          from: TrackingState.fromWire(t.fromState),
          to: nextState,
          // Il backend non restituisce il motivo della transizione originale.
          reason: _replayTransitionReason,
          timestamp: t.timestamp,
        );
        currentState = nextState;
        nextTransitionIdx++;
        updated = true;
      }

      while (nextPointIdx < points.length &&
          !points[nextPointIdx].timestamp.isAfter(currentReplayTime)) {
        final p = points[nextPointIdx];
        _latestLatitude = p.latitude;
        _latestLongitude = p.longitude;
        _latestAccuracyMeters = p.accuracyMeters;
        latestSpeedMps = p.speedMps;
        nextPointIdx++;
        updated = true;
      }

      final remaining = endTime.difference(currentReplayTime);
      final replaySecondsRemaining = _replaySecondsRemaining(
        remaining,
        speedMultiplier,
      );

      if (updated || replaySecondsRemaining != null) {
        emitSnapshot(
          AcquisitionSnapshot(
            isTracking: true,
            trackingState: currentState,
            samplingProfile: SamplingProfile.forState(currentState),
            latestSigma: 0,
            latestSpeedMetersPerSecond: latestSpeedMps,
            lastTransition: lastFsmTransition,
            updatedAt: currentReplayTime,
            latitude: _latestLatitude,
            longitude: _latestLongitude,
            accuracyMeters: _latestAccuracyMeters,
            replaySecondsRemaining: replaySecondsRemaining,
            isReplay: true,
          ),
        );
      }

      if (remaining <= Duration.zero) {
        _replayTimer?.cancel();
      }
    });
  }

  Future<ReplayStopResult> _stopReplay() async {
    final cutoffTimestamp = currentSnapshot.updatedAt;
    _replayTimer?.cancel();

    if (_currentSessionId == null) {
      throw const UploadApiException('Invalid state for stopReplay');
    }

    final filteredPoints = (_replayPoints ?? const <CoreGpsPoint>[])
        .where((p) => !p.timestamp.isAfter(cutoffTimestamp))
        .toList();
    final filteredTransitions = (_replayTransitions ??
            const <CoreStateTransition>[])
        .where((t) => !t.timestamp.isAfter(cutoffTimestamp))
        .toList();

    final now = DateTime.now().toUtc();
    final firstSourceTimestamp = [
      ...filteredPoints.map((p) => p.timestamp),
      ...filteredTransitions.map((t) => t.timestamp),
    ].fold<DateTime?>(null, (earliest, timestamp) {
      if (earliest == null || timestamp.isBefore(earliest)) return timestamp;
      return earliest;
    });
    final scheduledStartAt = _scheduledStartAt;
    final shift = scheduledStartAt != null && firstSourceTimestamp != null
        ? scheduledStartAt.difference(firstSourceTimestamp)
        : now.difference(cutoffTimestamp);
    final replayEndedAt =
        scheduledStartAt != null ? cutoffTimestamp.add(shift) : now;

    // Il viaggio rigiocato viene ricollocato nel tempo: ogni campione slitta
    // dello stesso offset, cosi' il backend lo riceve come se fosse appena
    // accaduto (o allo slot scelto dall'utente).
    final shiftedPoints = [
      for (final point in filteredPoints) point.shiftedBy(shift),
    ];
    final shiftedTransitions = [
      for (final transition in filteredTransitions) transition.shiftedBy(shift),
    ];

    final firstShiftedTs = shiftedPoints.isNotEmpty
        ? shiftedPoints.first.timestamp
        : (shiftedTransitions.isNotEmpty
            ? shiftedTransitions.first.timestamp
            : now);

    final corePayload = TripCorePayload(
      _mapper.toCorePayloadJson(
        clientSessionId: _currentSessionId!,
        deviceId: _currentDeviceId ?? '',
        gpsPoints: shiftedPoints,
        transitions: shiftedTransitions,
        expectedRawParts: 0,
        startedAt: firstShiftedTs,
        endedAt: replayEndedAt,
        uploadId: _currentRemoteUploadId,
        cutoffSourceTimestamp: cutoffTimestamp,
      ),
    );
    final response =
        await _uploadService?.postCoreInline(body: corePayload.requestBody);

    if (response == null) {
      throw const UploadApiException('Network error during stopReplay');
    }

    _currentSessionId = null;
    _currentRemoteUploadId = null;
    _currentDeviceId = null;
    _replayStartWallClock = null;
    _replayPoints = null;
    _replayTransitions = null;
    emitSnapshot(AcquisitionSnapshot.idle());

    return ReplayStopResult(tripId: response.tripId);
  }

  int? _currentReplayOffsetSeconds() {
    final start = _replayStartWallClock;
    if (start == null) return null;
    final elapsed = DateTime.now().difference(start);
    return (elapsed.inMilliseconds * _replaySpeed / 1000).round();
  }

  int? _replaySecondsRemaining(
    Duration sourceRemaining,
    double speedMultiplier,
  ) {
    final sourceSeconds = sourceRemaining.inSeconds;
    if (sourceSeconds > (15 * speedMultiplier).ceil()) return null;
    if (sourceSeconds <= 0) return 0;
    return (sourceSeconds / speedMultiplier).ceil();
  }

  DateTime? _earlier(DateTime? first, DateTime? second) {
    if (first == null) return second;
    if (second == null) return first;
    return first.isBefore(second) ? first : second;
  }

  DateTime? _later(DateTime? first, DateTime? second) {
    if (first == null) return second;
    if (second == null) return first;
    return first.isAfter(second) ? first : second;
  }



  Future<String> _resolveDeviceId() async {
    final provider = _deviceIdProvider;
    if (provider == null) {
      return _deviceId;
    }
    return provider();
  }
}
