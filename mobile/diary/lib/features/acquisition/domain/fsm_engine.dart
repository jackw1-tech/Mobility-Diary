import 'sampling_profile.dart';
import 'tracking_event.dart';
import 'tracking_state.dart';

class FsmConfig {
  final double movementSigmaThreshold;
  final int requiredMotionWindows;
  final int requiredReliableGpsMotionFixes;
  final int requiredUnreliableGpsMotionFixes;
  final double movementSpeedThresholdMetersPerSecond;
  final double reliableGpsAccuracyMeters;
  final Duration stationaryDeepAfter;
  final Duration movementStationaryGracePeriod;
  final int requiredConsecutiveMotionWindowsToHoldMovement;
  final int requiredReliableGpsReadingsToHoldMovement;
  final int requiredUnreliableGpsReadingsToHoldMovement;

  const FsmConfig({
    this.movementSigmaThreshold = 1,
    this.requiredMotionWindows = 4,
    this.requiredReliableGpsMotionFixes = 2,
    this.requiredUnreliableGpsMotionFixes = 3,
    this.movementSpeedThresholdMetersPerSecond = 2 / 3.6,
    this.reliableGpsAccuracyMeters = 35,
    this.stationaryDeepAfter = const Duration(minutes: 10),
    this.movementStationaryGracePeriod = const Duration(minutes: 2),
    // Nel ramo movement -> stationary il sigma ha priorita': basta la stessa
    // soglia dell'ingresso. Il GPS invece deve insistere piu' a lungo, e
    // ancora di piu' se il fix e' impreciso (rumore Doppler/multipath tipico
    // indoor) — stessa filosofia "affidabile vs inaffidabile" gia' usata in
    // ingresso, ma tarata piu' stretta perche' qui il rischio e' restare
    // bloccati in movement, non perdere l'inizio di un movimento reale.
    this.requiredConsecutiveMotionWindowsToHoldMovement = 2,
    this.requiredReliableGpsReadingsToHoldMovement = 3,
    this.requiredUnreliableGpsReadingsToHoldMovement = 5,
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

class AcquisitionFsm {
  final FsmConfig config;

  TrackingState _state;
  int _consecutiveMotionWindows = 0;
  int _movementReliableGpsMotionFixes = 0;
  int _movementUnreliableGpsMotionFixes = 0;
  int _stationaryReliableGpsMotionFixes = 0;
  int _stationaryUnreliableGpsMotionFixes = 0;
  double _latestSigma = 0;
  double _latestSpeedMetersPerSecond = 0;
  DateTime? _stationaryStartedAt;
  DateTime? _stationaryEvidenceStartedAt;

  AcquisitionFsm({
    this.config = const FsmConfig(),
    TrackingState initialState = TrackingState.stationary,
  }) : _state = initialState;

  double get latestSigma => _latestSigma;

  double get latestSpeedMetersPerSecond => _latestSpeedMetersPerSecond;

  TrackingState? get currentState => _state;

  void forceState(TrackingState state, double sigma, double speedMps) {
    _state = state;
    _latestSigma = sigma;
    _latestSpeedMetersPerSecond = speedMps;
  }

  FsmDecision apply(TrackingEvent event) {
    switch (event) {
      case MotionWindowEvaluated():
        return _onMotionWindow(event);
      case GpsFixReceived():
        return _onGpsFix(event);
    }
  }

  FsmDecision _onMotionWindow(MotionWindowEvaluated event) {
    _latestSigma = event.sigma;
    _consecutiveMotionWindows =
        _isMotion(event.sigma) ? _consecutiveMotionWindows + 1 : 0;

    if (_state == TrackingState.stationary) {
      if (_consecutiveMotionWindows >= config.requiredMotionWindows) {
        return _transitionTo(
          TrackingState.movement,
          'movement_sigma_above_threshold',
          event.timestamp,
        );
      }
      return _stay(event.timestamp);
    }

    return _evaluateMovementStationaryEvidence(event.timestamp);
  }

  FsmDecision _onGpsFix(GpsFixReceived event) {
    _latestSpeedMetersPerSecond = event.speedMetersPerSecond;
    _updateMovementGpsEvidence(event);

    if (_state == TrackingState.stationary) {
      return _onStationaryGpsFix(event);
    }

    return _evaluateMovementStationaryEvidence(event.timestamp);
  }

  // Tiene traccia, indipendentemente dallo stato, di quante letture GPS "in
  // moto" si sono accumulate dall'ultimo vero calo di velocita', separando
  // affidabili e inaffidabili — usato dal ramo movement -> stationary per
  // decidere se fidarsi del GPS.
  //
  // NON azzeriamo il contatore dell'altra categoria quando cambia solo la
  // classe di affidabilita' del fix: mentre ci si muove davvero l'accuratezza
  // GPS oscilla di continuo intorno alla soglia (35m), quindi i fix passano
  // spesso da affidabili a inaffidabili e viceversa. Se ogni oscillazione
  // resettasse l'altro contatore, nessuno dei due raggiungerebbe mai la
  // soglia e l'FSM ricadrebbe erroneamente in stationary (percorso live che
  // "si ferma"). Solo un fix SOTTO la soglia di movimento — cioe' una
  // decelerazione reale — azzera l'evidenza.
  void _updateMovementGpsEvidence(GpsFixReceived event) {
    if (!_isMovementSpeed(event.speedMetersPerSecond)) {
      _movementReliableGpsMotionFixes = 0;
      _movementUnreliableGpsMotionFixes = 0;
      return;
    }

    if (_isReliableGpsFix(event)) {
      _movementReliableGpsMotionFixes += 1;
    } else {
      _movementUnreliableGpsMotionFixes += 1;
    }
  }

  FsmDecision _onStationaryGpsFix(GpsFixReceived event) {
    if (!_isMovementSpeed(event.speedMetersPerSecond)) {
      _resetStationaryGpsEvidence();
      return _stay(event.timestamp);
    }

    if (_isReliableGpsFix(event)) {
      _stationaryReliableGpsMotionFixes += 1;
      _stationaryUnreliableGpsMotionFixes = 0;
      if (_stationaryReliableGpsMotionFixes >=
          config.requiredReliableGpsMotionFixes) {
        return _transitionTo(
          TrackingState.movement,
          'gps_reliable_motion_confirmed_in_stationary',
          event.timestamp,
        );
      }
      return _stay(event.timestamp);
    }

    _stationaryUnreliableGpsMotionFixes += 1;
    _stationaryReliableGpsMotionFixes = 0;
    if (_stationaryUnreliableGpsMotionFixes >=
        config.requiredUnreliableGpsMotionFixes) {
      return _transitionTo(
        TrackingState.movement,
        'gps_unreliable_motion_confirmed_in_stationary',
        event.timestamp,
      );
    }

    return _stay(event.timestamp);
  }

  FsmDecision _evaluateMovementStationaryEvidence(DateTime timestamp) {
    // Ogni canale ha il proprio contatore di letture "in moto" (sigma sopra
    // soglia in _onMotionWindow; velocita' sopra soglia in _onGpsFix),
    // azzerato solo da una lettura dello stesso canale che NON indica moto.
    // Una singola lettura rumorosa isolata su un canale (rumore Doppler/
    // multipath GPS, uno spike accelerometrico) non basta da sola: serve che
    // ALMENO UN canale accumuli abbastanza evidenza propria per essere
    // considerata moto reale sostenuta, non solo il valore piu' recente
    // (possibilmente stantio) dell'altro canale.
    //
    // Il sigma ha priorita': gli basta la stessa soglia dell'ingresso (2). Il
    // GPS deve insistere di piu' per essere creduto qui, ed e' pesato per
    // affidabilita' del fix, come gia' avviene in ingresso.
    final sustainedMotion = _consecutiveMotionWindows >=
            config.requiredConsecutiveMotionWindowsToHoldMovement ||
        _movementReliableGpsMotionFixes >=
            config.requiredReliableGpsReadingsToHoldMovement ||
        _movementUnreliableGpsMotionFixes >=
            config.requiredUnreliableGpsReadingsToHoldMovement;

    if (sustainedMotion) {
      _stationaryEvidenceStartedAt = null;
      return _stay(timestamp);
    }

    _stationaryEvidenceStartedAt ??= timestamp;
    final stationaryDuration = timestamp.difference(
      _stationaryEvidenceStartedAt!,
    );
    if (stationaryDuration >= config.movementStationaryGracePeriod) {
      return _transitionTo(
        TrackingState.stationary,
        'gps_and_motion_stationary_for_grace_period',
        timestamp,
      );
    }

    return _stay(timestamp);
  }

  FsmDecision _transitionTo(
    TrackingState nextState,
    String reason,
    DateTime timestamp,
  ) {
    final previousState = _state;
    _state = nextState;
    _consecutiveMotionWindows = 0;
    _movementReliableGpsMotionFixes = 0;
    _movementUnreliableGpsMotionFixes = 0;
    _stationaryEvidenceStartedAt = null;
    _resetStationaryGpsEvidence();

    if (nextState == TrackingState.stationary) {
      _stationaryStartedAt = timestamp;
    } else {
      _stationaryStartedAt = null;
    }

    return FsmDecision(
      state: _state,
      samplingProfile: _samplingProfileFor(timestamp),
      transition: FsmTransition(
        from: previousState,
        to: nextState,
        reason: reason,
        timestamp: timestamp,
      ),
    );
  }

  FsmDecision _stay(DateTime timestamp) {
    if (_state == TrackingState.stationary) {
      _stationaryStartedAt ??= timestamp;
    }

    return FsmDecision(
      state: _state,
      samplingProfile: _samplingProfileFor(timestamp),
    );
  }

  SamplingProfile _samplingProfileFor(DateTime timestamp) {
    if (_state == TrackingState.movement) {
      return SamplingProfile.forState(_state);
    }

    final stationaryStartedAt = _stationaryStartedAt ?? timestamp;
    final stationaryDuration = timestamp.difference(stationaryStartedAt);
    return SamplingProfile.forState(
      _state,
      stationaryDeep: stationaryDuration >= config.stationaryDeepAfter,
    );
  }

  bool _isMotion(double sigma) => sigma > config.movementSigmaThreshold;

  bool _isMovementSpeed(double speedMetersPerSecond) {
    return speedMetersPerSecond > config.movementSpeedThresholdMetersPerSecond;
  }

  bool _isReliableGpsFix(GpsFixReceived event) {
    final accuracyMeters = event.accuracyMeters;
    return accuracyMeters == null ||
        accuracyMeters <= config.reliableGpsAccuracyMeters;
  }

  void _resetStationaryGpsEvidence() {
    _stationaryReliableGpsMotionFixes = 0;
    _stationaryUnreliableGpsMotionFixes = 0;
  }
}
