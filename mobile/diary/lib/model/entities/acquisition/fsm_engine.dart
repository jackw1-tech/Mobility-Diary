import 'sampling_profile.dart';
import 'tracking_event.dart';
import 'tracking_state.dart';

class FsmConfig {
  final Duration movingEvidenceRequired;
  final Duration stationaryEvidenceRequired;
  final Duration stationaryUncertainGrace;
  final Duration motionSigmaFreshness;
  final Duration gpsSpeedFreshness;
  final double movingGpsSpeedThresholdMps;
  final double vehicleGpsSpeedThresholdMps;
  final double stationaryGpsSpeedThresholdMps;
  final double movingMotionSigmaThreshold;
  final double stationaryMotionSigmaThreshold;

  const FsmConfig({
    this.movingEvidenceRequired = const Duration(seconds: 6),
    this.stationaryEvidenceRequired = const Duration(seconds: 120),
    this.stationaryUncertainGrace = const Duration(seconds: 20),
    this.motionSigmaFreshness = const Duration(seconds: 10),
    this.gpsSpeedFreshness = const Duration(seconds: 20),
    this.movingGpsSpeedThresholdMps = 0.8,
    this.vehicleGpsSpeedThresholdMps = 2.5,
    this.stationaryGpsSpeedThresholdMps = 0.4,
    this.movingMotionSigmaThreshold = 1.2,
    this.stationaryMotionSigmaThreshold = 0.8,
  });
}

class FsmTransition {
  final TrackingState from;
  final TrackingState to;
  final String reason;
  final DateTime timestamp;

  const FsmTransition({
    required this.from,
    required this.to,
    required this.reason,
    required this.timestamp,
  });
}

class FsmDecision {
  final TrackingState state;
  final SamplingProfile samplingProfile;
  final FsmTransition? transition;

  const FsmDecision({
    required this.state,
    required this.samplingProfile,
    this.transition,
  });

  bool get didTransition => transition != null;
}

enum _MotionEvidence {
  moving,
  stationary,
  uncertain,
}

enum FsmEvidenceMode {
  /// Inerziale fresco: la decisione incrocia sigma accelerometrico e velocita'
  /// GPS.
  strictSensors,

  /// App in background: iOS smette di consegnare gli eventi CoreMotion, quindi
  /// il sigma diventa stale. La velocita' GPS invece continua ad arrivare ed e'
  /// l'unica prova affidabile: decidere solo con quella, mai dichiarare fermo
  /// un viaggio solo perche' l'inerziale tace.
  gpsOnly,
}

class AcquisitionFsm {
  final FsmConfig config;

  TrackingState _state;
  double _latestSigma = 0;
  double _latestGpsSpeedMetersPerSecond = 0;
  DateTime? _latestSigmaAt;
  DateTime? _latestGpsSpeedAt;
  DateTime? _movingEvidenceStartedAt;
  DateTime? _stationaryEvidenceStartedAt;
  DateTime? _stationaryUncertainStartedAt;

  AcquisitionFsm({
    this.config = const FsmConfig(),
    TrackingState initialState = TrackingState.stationary,
  }) : _state = initialState;

  double get latestSigma => _latestSigma;

  double get latestSpeedMetersPerSecond => _latestGpsSpeedMetersPerSecond;

  TrackingState? get currentState => _state;

  void forceState(TrackingState state, double sigma, double speedMps) {
    _state = state;
    _latestSigma = sigma;
    _latestGpsSpeedMetersPerSecond = speedMps;
    _latestSigmaAt = null;
    _latestGpsSpeedAt = null;
    _movingEvidenceStartedAt = null;
    _stationaryEvidenceStartedAt = null;
    _stationaryUncertainStartedAt = null;
  }

  FsmDecision apply(
    TrackingEvent event, {
    FsmEvidenceMode evidenceMode = FsmEvidenceMode.strictSensors,
  }) {
    _updateSignal(event);
    final evidence = _evidenceAt(event.timestamp, evidenceMode);

    switch (_state) {
      case TrackingState.stationary:
        return _evaluateStationary(evidence, event.timestamp);
      case TrackingState.movement:
        return _evaluateMovement(evidence, event.timestamp);
    }
  }

  void _updateSignal(TrackingEvent event) {
    switch (event) {
      case MotionWindowEvaluated():
        _latestSigma = event.sigma;
        _latestSigmaAt = event.timestamp;
      case GpsFixReceived():
        _latestGpsSpeedMetersPerSecond = event.speedMetersPerSecond;
        _latestGpsSpeedAt = event.timestamp;
    }
  }

  FsmDecision _evaluateStationary(
    _MotionEvidence evidence,
    DateTime timestamp,
  ) {
    switch (evidence) {
      case _MotionEvidence.moving:
        _movingEvidenceStartedAt ??= timestamp;
        final duration = timestamp.difference(_movingEvidenceStartedAt!);
        if (duration >= config.movingEvidenceRequired) {
          return _transitionTo(
            TrackingState.movement,
            'moving_evidence_confirmed',
            timestamp,
          );
        }
      case _MotionEvidence.stationary:
        _movingEvidenceStartedAt = null;
      case _MotionEvidence.uncertain:
        _movingEvidenceStartedAt = null;
    }

    return _stay();
  }

  FsmDecision _evaluateMovement(
    _MotionEvidence evidence,
    DateTime timestamp,
  ) {
    switch (evidence) {
      case _MotionEvidence.stationary:
        if (_stationaryUncertainExceededGrace(timestamp)) {
          _stationaryEvidenceStartedAt = timestamp;
        }
        _stationaryUncertainStartedAt = null;
        _stationaryEvidenceStartedAt ??= timestamp;
        final duration = timestamp.difference(_stationaryEvidenceStartedAt!);
        if (duration >= config.stationaryEvidenceRequired) {
          return _transitionTo(
            TrackingState.stationary,
            'stationary_evidence_confirmed',
            timestamp,
          );
        }
      case _MotionEvidence.moving:
        _stationaryEvidenceStartedAt = null;
        _stationaryUncertainStartedAt = null;
      case _MotionEvidence.uncertain:
        _evaluateUncertainWhileSettlingStationary(timestamp);
    }

    return _stay();
  }

  _MotionEvidence _evidenceAt(
    DateTime timestamp,
    FsmEvidenceMode evidenceMode,
  ) {
    final gpsSpeed = _freshGpsSpeed(timestamp);
    if (gpsSpeed == null) {
      return _MotionEvidence.uncertain;
    }

    if (gpsSpeed >= config.vehicleGpsSpeedThresholdMps) {
      return _MotionEvidence.moving;
    }

    if (evidenceMode == FsmEvidenceMode.gpsOnly) {
      return _gpsOnlyEvidence(gpsSpeed);
    }

    final sigma = _freshSigma(timestamp);
    if (sigma == null) {
      return _MotionEvidence.uncertain;
    }

    if (sigma >= config.movingMotionSigmaThreshold &&
        gpsSpeed >= config.movingGpsSpeedThresholdMps) {
      return _MotionEvidence.moving;
    }

    if (sigma < config.stationaryMotionSigmaThreshold &&
        gpsSpeed < config.stationaryGpsSpeedThresholdMps) {
      return _MotionEvidence.stationary;
    }

    return _MotionEvidence.uncertain;
  }

  /// Senza inerziale fresco resta solo la velocita' GPS: sopra la soglia di
  /// movimento e' moto confermato (anche a piedi), sotto quella di fermo e'
  /// fermo confermato, in mezzo si resta incerti e decidono i debounce.
  _MotionEvidence _gpsOnlyEvidence(double gpsSpeed) {
    if (gpsSpeed >= config.movingGpsSpeedThresholdMps) {
      return _MotionEvidence.moving;
    }
    if (gpsSpeed < config.stationaryGpsSpeedThresholdMps) {
      return _MotionEvidence.stationary;
    }
    return _MotionEvidence.uncertain;
  }

  double? _freshSigma(DateTime timestamp) {
    final latestAt = _latestSigmaAt;
    if (latestAt == null ||
        timestamp.difference(latestAt) > config.motionSigmaFreshness) {
      return null;
    }
    return _latestSigma;
  }

  double? _freshGpsSpeed(DateTime timestamp) {
    final latestAt = _latestGpsSpeedAt;
    if (latestAt == null ||
        timestamp.difference(latestAt) > config.gpsSpeedFreshness) {
      return null;
    }
    return _latestGpsSpeedMetersPerSecond;
  }

  FsmDecision _transitionTo(
    TrackingState nextState,
    String reason,
    DateTime timestamp,
  ) {
    final previousState = _state;
    _state = nextState;
    _movingEvidenceStartedAt = null;
    _stationaryEvidenceStartedAt = null;
    _stationaryUncertainStartedAt = null;

    return FsmDecision(
      state: _state,
      samplingProfile: _samplingProfileFor(),
      transition: FsmTransition(
        from: previousState,
        to: nextState,
        reason: reason,
        timestamp: timestamp,
      ),
    );
  }

  FsmDecision _stay() {
    return FsmDecision(
      state: _state,
      samplingProfile: _samplingProfileFor(),
    );
  }

  void _evaluateUncertainWhileSettlingStationary(DateTime timestamp) {
    if (_stationaryEvidenceStartedAt == null) {
      _stationaryUncertainStartedAt = null;
      return;
    }

    _stationaryUncertainStartedAt ??= timestamp;
    final uncertainDuration = timestamp.difference(
      _stationaryUncertainStartedAt!,
    );
    if (uncertainDuration > config.stationaryUncertainGrace) {
      _stationaryEvidenceStartedAt = null;
      _stationaryUncertainStartedAt = null;
    }
  }

  bool _stationaryUncertainExceededGrace(DateTime timestamp) {
    final uncertainStartedAt = _stationaryUncertainStartedAt;
    return uncertainStartedAt != null &&
        timestamp.difference(uncertainStartedAt) >
            config.stationaryUncertainGrace;
  }

  SamplingProfile _samplingProfileFor() {
    return SamplingProfile.forState(_state);
  }
}
