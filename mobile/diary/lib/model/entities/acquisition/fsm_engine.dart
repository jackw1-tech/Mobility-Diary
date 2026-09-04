import 'sampling_profile.dart';
import 'tracking_event.dart';
import 'tracking_state.dart';

class FsmConfig {
  final Duration movingEvidenceRequired;
  final Duration stationaryEvidenceRequired;
  final Duration motionSigmaFreshness;
  final Duration gpsSpeedFreshness;
  final double movingGpsSpeedThresholdMps;
  final double vehicleGpsSpeedThresholdMps;
  final double stationaryGpsSpeedThresholdMps;
  final double movingMotionSigmaThreshold;
  final double stationaryMotionSigmaThreshold;

  const FsmConfig({
    this.movingEvidenceRequired = const Duration(seconds: 5),
    this.stationaryEvidenceRequired = const Duration(seconds: 120),
    this.motionSigmaFreshness = const Duration(seconds: 10),
    this.gpsSpeedFreshness = const Duration(seconds: 20),
    this.movingGpsSpeedThresholdMps = 0.8,
    this.vehicleGpsSpeedThresholdMps = 2.5,
    this.stationaryGpsSpeedThresholdMps = 0.5,
    this.movingMotionSigmaThreshold = 1.2,
    this.stationaryMotionSigmaThreshold = 0.8,
  });
}

class FsmTransition {
  final TrackingState from;
  final TrackingState to;
  final DateTime timestamp;

  const FsmTransition({
    required this.from,
    required this.to,
    required this.timestamp,
  });
}

class FsmDecision {
  final TrackingState state;
  final SamplingProfile samplingProfile;
  final FsmTransition? transition;
  final FsmDecisionDiagnostics diagnostics;

  const FsmDecision({
    required this.state,
    required this.samplingProfile,
    required this.diagnostics,
    this.transition,
  });

  bool get didTransition => transition != null;
}

enum MotionEvidence {
  moving,
  stationary,
  uncertain,
}

enum StationaryTimerAction {
  notApplicable,
  idle,
  started,
  accumulating,
  preserved,
  reset,
  transitioned,
}

class FsmDecisionDiagnostics {
  final TrackingState previousState;
  final MotionEvidence evidence;
  final FsmEvidenceMode evidenceMode;
  final double sigma;
  final double gpsSpeedMetersPerSecond;
  final Duration? sigmaAge;
  final Duration? gpsSpeedAge;
  final StationaryTimerAction stationaryTimerAction;
  final Duration? stationaryEvidenceElapsed;

  const FsmDecisionDiagnostics({
    required this.previousState,
    required this.evidence,
    required this.evidenceMode,
    required this.sigma,
    required this.gpsSpeedMetersPerSecond,
    required this.sigmaAge,
    required this.gpsSpeedAge,
    required this.stationaryTimerAction,
    required this.stationaryEvidenceElapsed,
  });
}

class _FsmOutcome {
  final TrackingState state;
  final SamplingProfile samplingProfile;
  final FsmTransition? transition;

  const _FsmOutcome({
    required this.state,
    required this.samplingProfile,
    this.transition,
  });
}

enum FsmEvidenceMode {
  inertialAndGps,
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
  }

  // Richiamo la funzione che classifica il singolo evento e poi in base allo stato attuale decido
  FsmDecision apply(
    TrackingEvent event, {
    FsmEvidenceMode evidenceMode = FsmEvidenceMode.inertialAndGps,
  }) {
    final previousState = _state;
    final stationaryEvidenceStartedAt = _stationaryEvidenceStartedAt;
    _updateSignal(event);
    final evidence = _evidenceAt(event.timestamp, evidenceMode);

    final outcome = switch (_state) {
      TrackingState.stationary =>
        _evaluateStationary(evidence, event.timestamp),
      TrackingState.movement => _evaluateMovement(evidence, event.timestamp),
    };

    return FsmDecision(
      state: outcome.state,
      samplingProfile: outcome.samplingProfile,
      transition: outcome.transition,
      diagnostics: _diagnosticsFor(
        timestamp: event.timestamp,
        evidenceMode: evidenceMode,
        evidence: evidence,
        previousState: previousState,
        stationaryEvidenceStartedAt: stationaryEvidenceStartedAt,
        outcome: outcome,
      ),
    );
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

  // In partenza siamo stationary, valuto la nuova evidenza
  _FsmOutcome _evaluateStationary(
    MotionEvidence evidence,
    DateTime timestamp,
  ) {
    switch (evidence) {
      case MotionEvidence.moving:
        _movingEvidenceStartedAt ??=
            timestamp; // prima volta che arriva un evidenza di movimento -> assegna solo se _movingEvidenceStartedAt è vuoto
        final duration = timestamp.difference(_movingEvidenceStartedAt!);
        if (duration >= config.movingEvidenceRequired) {
          return _transitionTo(TrackingState.movement, timestamp);
          // Per decretare che sono in movimento devo avere evidenza di movimento per almeno 5 secondi
        }
      case MotionEvidence.stationary:
        _movingEvidenceStartedAt = null;
      // Incerto: nessuna nuova informazione, il conteggio resta com'e'.
      case MotionEvidence.uncertain:
    }

    return _stay();
  }

  // Sono in movimento, valuto i nuovi dati
  _FsmOutcome _evaluateMovement(
    MotionEvidence evidence,
    DateTime timestamp,
  ) {
    switch (evidence) {
      case MotionEvidence.stationary:
        _stationaryEvidenceStartedAt ??=
            timestamp; // _stationaryEvidenceStartedAt viene assegnato con il primo valore di evidenzia
        // di stazionary, viene assegnato solo se è null
        final duration = timestamp.difference(_stationaryEvidenceStartedAt!);
        if (duration >= config.stationaryEvidenceRequired) {
          return _transitionTo(TrackingState.stationary, timestamp);
        }
      case MotionEvidence.moving:
        _stationaryEvidenceStartedAt = null;
      // Incerto: nessuna nuova informazione, il conteggio resta com'e'.
      case MotionEvidence.uncertain:
    }

    return _stay();
  }

  //Classificatore del singolo evento che arriva dai sensori o gps
  MotionEvidence _evidenceAt(
    DateTime timestamp,
    FsmEvidenceMode evidenceMode,
  ) {
    // Gps come primo filtro
    final gpsSpeed = _freshGpsSpeed(timestamp);
    if (gpsSpeed == null) {
      return MotionEvidence.uncertain;
    }

    // Circa 2.5 m/s (9 km/h) -> Sono in auto o in bici, non ho bisogno dell'accellerometro
    if (gpsSpeed >= config.vehicleGpsSpeedThresholdMps) {
      return MotionEvidence.moving;
    }

    if (evidenceMode == FsmEvidenceMode.gpsOnly) {
      return _gpsOnlyEvidence(gpsSpeed);
    }

    final sigma = _freshSigma(timestamp);
    if (sigma == null) {
      return MotionEvidence.uncertain;
    }

    // Non sono in auto e  ho dati recenti di accelerometro e gps
    if (sigma >= config.movingMotionSigmaThreshold &&
        gpsSpeed >= config.movingGpsSpeedThresholdMps) {
      return MotionEvidence.moving;
    }

    if (sigma < config.stationaryMotionSigmaThreshold &&
        gpsSpeed < config.stationaryGpsSpeedThresholdMps) {
      return MotionEvidence.stationary;
    }

    return MotionEvidence.uncertain;
  }

  // I dati dei sensori non sono recenti e non mi sto muovendo in auto
  // Due soglie invece di una per evitare troppe oscillazioni tra fermo e in movimento
  MotionEvidence _gpsOnlyEvidence(double gpsSpeed) {
    // 0.8 m/s = 2.88 km/h
    if (gpsSpeed >= config.movingGpsSpeedThresholdMps) {
      return MotionEvidence.moving;
    }
    // 0.5 m/s = 1.8 km/h,
    if (gpsSpeed < config.stationaryGpsSpeedThresholdMps) {
      return MotionEvidence.stationary;
    }
    return MotionEvidence.uncertain;
  }

  // Ottengo l'ultimo dato di sigma controllando se è abbastanza recente
  double? _freshSigma(DateTime timestamp) {
    final latestAt = _latestSigmaAt;
    if (latestAt == null ||
        timestamp.difference(latestAt) > config.motionSigmaFreshness) {
      return null;
    }
    return _latestSigma;
  }

  // Controllo che la decisione che sto per prendere si possa basare su un dato Gps Recente -> Gps speed recente
  double? _freshGpsSpeed(DateTime timestamp) {
    final latestAt = _latestGpsSpeedAt;
    if (latestAt == null ||
        timestamp.difference(latestAt) > config.gpsSpeedFreshness) {
      return null;
    }
    return _latestGpsSpeedMetersPerSecond;
  }

  // Cambio di stato, resetto i timer
  _FsmOutcome _transitionTo(
    TrackingState nextState,
    DateTime timestamp,
  ) {
    final previousState = _state;
    _state = nextState;
    _movingEvidenceStartedAt = null;
    _stationaryEvidenceStartedAt = null;

    return _FsmOutcome(
      state: _state,
      samplingProfile: _samplingProfileFor(),
      transition: FsmTransition(
        from: previousState,
        to: nextState,
        timestamp: timestamp,
      ),
    );
  }

  // Resto nello stato attuale
  _FsmOutcome _stay() {
    return _FsmOutcome(
      state: _state,
      samplingProfile: _samplingProfileFor(),
    );
  }

  SamplingProfile _samplingProfileFor() {
    return SamplingProfile.forState(_state);
  }

  FsmDecisionDiagnostics _diagnosticsFor({
    required DateTime timestamp,
    required FsmEvidenceMode evidenceMode,
    required MotionEvidence evidence,
    required TrackingState previousState,
    required DateTime? stationaryEvidenceStartedAt,
    required _FsmOutcome outcome,
  }) {
    final transitionedToStationary =
        outcome.transition?.to == TrackingState.stationary;
    final timerAction = switch (previousState) {
      TrackingState.stationary => StationaryTimerAction.notApplicable,
      TrackingState.movement when transitionedToStationary =>
        StationaryTimerAction.transitioned,
      TrackingState.movement => switch (evidence) {
          MotionEvidence.stationary => stationaryEvidenceStartedAt == null
              ? StationaryTimerAction.started
              : StationaryTimerAction.accumulating,
          MotionEvidence.moving => stationaryEvidenceStartedAt == null
              ? StationaryTimerAction.idle
              : StationaryTimerAction.reset,
          MotionEvidence.uncertain => stationaryEvidenceStartedAt == null
              ? StationaryTimerAction.idle
              : StationaryTimerAction.preserved,
        },
    };
    final elapsed = previousState == TrackingState.movement &&
            stationaryEvidenceStartedAt != null &&
            evidence != MotionEvidence.moving
        ? timestamp.difference(stationaryEvidenceStartedAt)
        : (previousState == TrackingState.movement &&
                evidence == MotionEvidence.stationary
            ? Duration.zero
            : null);

    return FsmDecisionDiagnostics(
      previousState: previousState,
      evidence: evidence,
      evidenceMode: evidenceMode,
      sigma: _latestSigma,
      gpsSpeedMetersPerSecond: _latestGpsSpeedMetersPerSecond,
      sigmaAge: _ageOf(timestamp, _latestSigmaAt),
      gpsSpeedAge: _ageOf(timestamp, _latestGpsSpeedAt),
      stationaryTimerAction: timerAction,
      stationaryEvidenceElapsed: elapsed,
    );
  }

  Duration? _ageOf(DateTime timestamp, DateTime? measuredAt) {
    return measuredAt == null ? null : timestamp.difference(measuredAt);
  }
}
