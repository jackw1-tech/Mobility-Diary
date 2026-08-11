import 'dart:async';

import 'package:diary/mappers/ingestion_mapper.dart';
import 'package:diary/model/entities/acquisition/acquisition_domain.dart';
import 'package:diary/model/entities/acquisition/ingestion_models.dart';
import 'package:diary/repositories/acquisition_strategy.dart';
import 'package:diary/repositories/impl/acquisition/trip_package_builder.dart';
import 'package:diary/network/service/trip_ingestion_service.dart';
import 'package:diary/repositories/impl/acquisition/acquisition_snapshot_emitter.dart';
import 'package:diary/utils/date_time_utils.dart';
import 'package:uuid/uuid.dart';

typedef ReplayTimerFactory = Timer Function(
  Duration duration,
  void Function(Timer timer) callback,
);

class ReplayAcquisitionStrategy
    with AcquisitionSnapshotEmitter
    implements AcquisitionStrategy {
  final TripIngestionService? _ingestionService;
  final IngestionMapper _mapper;
  final Uuid _uuid;
  final String _deviceId;
  final Future<String> Function()? _deviceIdProvider;
  final int _sourceTripId;
  final DateTime? _scheduledStartAt;
  final double _requestedReplaySpeedMultiplier;
  final ReplayTimerFactory _timerFactory;

  Timer? _replayTimer;
  String? _currentSessionId;
  int? _currentRemoteIngestionId;
  String? _currentDeviceId;
  DateTime? _replayStartWallClock;
  double _replaySpeed = 1;
  List<Map<String, dynamic>>? _replayPoints;
  List<Map<String, dynamic>>? _replayTransitions;
  double? _latestLatitude;
  double? _latestLongitude;
  double? _latestAccuracyMeters;

  ReplayAcquisitionStrategy({
    required int sourceTripId,
    DateTime? scheduledStartAt,
    double replaySpeedMultiplier = 1,
    TripIngestionService? ingestionService,
    IngestionMapper? mapper,
    Uuid? uuid,
    String deviceId = 'local_device',
    Future<String> Function()? deviceIdProvider,
    ReplayTimerFactory? timerFactory,
  })  : _sourceTripId = sourceTripId,
        _scheduledStartAt = scheduledStartAt?.toUtc(),
        _requestedReplaySpeedMultiplier = replaySpeedMultiplier,
        _ingestionService = ingestionService,
        _mapper = mapper ?? IngestionMapper(),
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

    IngestionStartResult? remoteStart;
    try {
      final startDto = await _ingestionService?.startIngestion(
        clientSessionId: sessionId,
        startedAt: now,
        deviceId: deviceId,
        sourceTripId: _sourceTripId,
      );
      remoteStart =
          startDto == null ? null : _mapper.mapIngestionStartResult(startDto);
    } on IngestionApiException {
      throw const IngestionApiException('Richiesta ingestion fallita');
    }

    final replayData = await _ingestionService?.getReplayData(_sourceTripId);
    if (replayData == null) {
      throw const IngestionApiException('Richiesta ingestion fallita');
    }

    _currentSessionId = sessionId;
    _currentRemoteIngestionId = remoteStart?.ingestionId;
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
      replayData,
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
      return await _ingestionService?.getReplaySensorWindow(
            _sourceTripId,
            offset,
          ) ??
          const [];
    } on IngestionApiException {
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
    Map<String, dynamic> data, {
    required double speedMultiplier,
  }) {
    final rawPoints = data['gps_points'] as List<dynamic>? ??
        data['points'] as List<dynamic>? ??
        [];
    final rawTransitions = data['state_transitions'] as List<dynamic>? ??
        data['transitions'] as List<dynamic>? ??
        [];

    if (rawPoints.isEmpty && rawTransitions.isEmpty) {
      emitSnapshot(AcquisitionSnapshot.idle());
      return;
    }

    DateTime pTime(dynamic p) =>
        DateTime.parse(p['timestamp'] as String).toUtc();

    _replayPoints = List<Map<String, dynamic>>.from(rawPoints)
      ..sort((a, b) => pTime(a).compareTo(pTime(b)));
    _replayTransitions = List<Map<String, dynamic>>.from(rawTransitions)
      ..sort((a, b) => pTime(a).compareTo(pTime(b)));

    final points = _replayPoints!;
    final transitions = _replayTransitions!;

    final firstPoint = points.isNotEmpty ? pTime(points.first) : null;
    final firstTransition =
        transitions.isNotEmpty ? pTime(transitions.first) : null;
    final lastPoint = points.isNotEmpty ? pTime(points.last) : null;
    final lastTransition =
        transitions.isNotEmpty ? pTime(transitions.last) : null;
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
          !pTime(transitions[nextTransitionIdx]).isAfter(currentReplayTime)) {
        final t = transitions[nextTransitionIdx];
        final nextState = TrackingState.fromWire(t['to_state'] as String);
        lastFsmTransition = FsmTransition(
          from: TrackingState.fromWire(t['from_state'] as String),
          to: nextState,
          reason: t['reason'] as String? ?? 'replay',
          timestamp: pTime(t),
        );
        currentState = nextState;
        nextTransitionIdx++;
        updated = true;
      }

      while (nextPointIdx < points.length &&
          !pTime(points[nextPointIdx]).isAfter(currentReplayTime)) {
        final p = points[nextPointIdx];
        _latestLatitude = (p['latitude'] as num).toDouble();
        _latestLongitude = (p['longitude'] as num).toDouble();
        _latestAccuracyMeters = (p['accuracy_meters'] as num?)?.toDouble();
        latestSpeedMps = (p['speed_mps'] as num?)?.toDouble() ?? 0;
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
      throw const IngestionApiException('Invalid state for stopReplay');
    }

    DateTime pTime(dynamic p) =>
        DateTime.parse(p['timestamp'] as String).toUtc();

    final filteredPoints = (_replayPoints ?? const <Map<String, dynamic>>[])
        .where((p) => !pTime(p).isAfter(cutoffTimestamp))
        .toList();
    final filteredTransitions =
        (_replayTransitions ?? const <Map<String, dynamic>>[])
            .where((t) => !pTime(t).isAfter(cutoffTimestamp))
            .toList();

    final now = DateTime.now().toUtc();
    final firstSourceTimestamp = [
      ...filteredPoints.map(pTime),
      ...filteredTransitions.map(pTime),
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

    String shiftIso(DateTime original) =>
        DateTimeUtils.toUtcIso(original.add(shift));

    final shiftedPoints = filteredPoints.map((p) {
      return {
        ...p,
        'timestamp': shiftIso(pTime(p)),
      };
    }).toList();

    final shiftedTransitions = filteredTransitions.map((t) {
      return {
        'from_state': t['from_state'],
        'to_state': t['to_state'],
        'reason': t['reason'] ?? '',
        'sigma': t['sigma'],
        'speed_mps': t['speed_mps'],
        'timestamp': shiftIso(pTime(t)),
      };
    }).toList();

    final firstShiftedTs = shiftedPoints.isNotEmpty
        ? DateTime.parse(shiftedPoints.first['timestamp'] as String).toUtc()
        : (shiftedTransitions.isNotEmpty
            ? DateTime.parse(shiftedTransitions.first['timestamp'] as String)
                .toUtc()
            : now);

    final payload = {
      'app_version': '',
      'client_session_id': _currentSessionId,
      'device_id': _currentDeviceId ?? '',
      'device_platform': '',
      'ended_at': DateTimeUtils.toUtcIso(replayEndedAt),
      'cutoff_source_timestamp': DateTimeUtils.toUtcIso(cutoffTimestamp),
      'expected_raw_parts': 0,
      'gps_points': shiftedPoints,
      if (_currentRemoteIngestionId != null)
        'ingestion_id': _currentRemoteIngestionId,
      'schema_version': 1,
      'started_at': DateTimeUtils.toUtcIso(firstShiftedTs),
      'state_transitions': shiftedTransitions,
      'timezone': '',
    };

    final corePayload = TripCorePayload(payload);
    final response =
        await _ingestionService?.postCoreInline(body: corePayload.requestBody);

    if (response == null) {
      throw const IngestionApiException('Network error during stopReplay');
    }

    _currentSessionId = null;
    _currentRemoteIngestionId = null;
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
