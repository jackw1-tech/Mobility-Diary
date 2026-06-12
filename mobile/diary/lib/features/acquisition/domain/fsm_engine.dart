import 'sampling_profile.dart';
import 'tracking_event.dart';
import 'tracking_state.dart';

class FsmConfig {
  final double movementSigmaThreshold;
  final int requiredMotionWindows;
  final int requiredPotentialMotionWindows;
  final int requiredPotentialStationaryWindows;
  final int requiredPotentialStationaryGpsFixes;
  final int requiredStationaryReliableGpsMotionFixes;
  final int requiredStationaryReliableGpsFastFixes;
  final int requiredStationaryUnreliableGpsMotionFixes;
  final int requiredStationaryUnreliableGpsFastFixes;
  final double activeSpeedThresholdMetersPerSecond;
  final double stationarySpeedThresholdMetersPerSecond;
  final double stationaryGpsActiveSpeedThresholdMetersPerSecond;
  final double potentialGpsReliableAccuracyMeters;
  final Duration stationaryDeepAfter;
  final Duration potentialMotionTimeout;
  final Duration activeStationaryGracePeriod;
  final Duration gpsFixFreshness;

  const FsmConfig({
    this.movementSigmaThreshold = 1,
    this.requiredMotionWindows = 4,
    this.requiredPotentialMotionWindows = 8,
    this.requiredPotentialStationaryWindows = 4,
    this.requiredPotentialStationaryGpsFixes = 2,
    this.requiredStationaryReliableGpsMotionFixes = 2,
    this.requiredStationaryReliableGpsFastFixes = 3,
    this.requiredStationaryUnreliableGpsMotionFixes = 3,
    this.requiredStationaryUnreliableGpsFastFixes = 3,
    this.activeSpeedThresholdMetersPerSecond = 2 / 3.6,
    this.stationarySpeedThresholdMetersPerSecond = 0.1,
    this.stationaryGpsActiveSpeedThresholdMetersPerSecond = 8 / 3.6,
    this.potentialGpsReliableAccuracyMeters = 35,
    this.stationaryDeepAfter = const Duration(minutes: 10),
    this.potentialMotionTimeout = const Duration(seconds: 60),
    this.activeStationaryGracePeriod = const Duration(minutes: 2),
    this.gpsFixFreshness = const Duration(seconds: 20),
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
  int _potentialMotionWindows = 0;
  int _potentialStationaryWindows = 0;
  int _potentialStationaryGpsFixes = 0;
  int _stationaryReliableGpsMotionFixes = 0;
  int _stationaryReliableGpsFastFixes = 0;
  int _stationaryUnreliableGpsMotionFixes = 0;
  int _stationaryUnreliableGpsFastFixes = 0;
  bool _hasReliablePotentialGpsFix = false;
  double _latestSigma = 0;
  double _latestSpeedMetersPerSecond = 0;
  double _latestReliablePotentialSpeedMetersPerSecond = 0;
  DateTime? _latestReliablePotentialGpsFixAt;
  DateTime? _stationaryStartedAt;
  DateTime? _stationaryEvidenceStartedAt;

  AcquisitionFsm({
    this.config = const FsmConfig(),
    TrackingState initialState = TrackingState.stationary,
  }) : _state = initialState;

  TrackingState get state => _state;

  int get consecutiveMotionWindows => _consecutiveMotionWindows;

  double get latestSigma => _latestSigma;

  double get latestSpeedMetersPerSecond => _latestSpeedMetersPerSecond;

  FsmDecision apply(TrackingEvent event) {
    switch (event) {
      case MotionWindowEvaluated():
        return _onMotionWindow(event);
      case GpsFixReceived():
        return _onGpsFix(event);
      case PotentialMotionTimeoutElapsed():
        return _onPotentialMotionTimeout(event);
    }
  }

  FsmDecision _onMotionWindow(MotionWindowEvaluated event) {
    _latestSigma = event.sigma;

    if (_isMotion(event.sigma)) {
      _consecutiveMotionWindows += 1;
    } else {
      _consecutiveMotionWindows = 0;
    }

    switch (_state) {
      case TrackingState.stationary:
        if (_consecutiveMotionWindows >= config.requiredMotionWindows) {
          return _transitionTo(
            TrackingState.potentialMotion,
            'movement_sigma_above_threshold',
            event.timestamp,
          );
        }
        return _stay(event.timestamp);
      case TrackingState.potentialMotion:
        if (_isMotion(event.sigma)) {
          _potentialMotionWindows += 1;
          _potentialStationaryWindows = 0;
        } else {
          _potentialMotionWindows = 0;
          _potentialStationaryWindows += 1;
        }

        if (_potentialStationaryWindows >=
            config.requiredPotentialStationaryWindows) {
          return _transitionTo(
            TrackingState.stationary,
            'potential_motion_stationary_windows',
            event.timestamp,
          );
        }

        if (!_hasReliablePotentialGpsFix &&
            _potentialMotionWindows >= config.requiredPotentialMotionWindows) {
          return _transitionTo(
            TrackingState.activeTracking,
            'sustained_motion_without_reliable_gps',
            event.timestamp,
          );
        }

        return _stay(event.timestamp);
      case TrackingState.activeTracking:
        return _evaluateActiveStationaryEvidence(event.timestamp);
    }
  }

  FsmDecision _onGpsFix(GpsFixReceived event) {
    _latestSpeedMetersPerSecond = event.speedMetersPerSecond;

    switch (_state) {
      case TrackingState.stationary:
        return _onStationaryGpsFix(event);
      case TrackingState.potentialMotion:
        final hasReliableGpsFix = _isReliableGpsFix(event);
        if (!hasReliableGpsFix) {
          return _stay(event.timestamp);
        }

        _hasReliablePotentialGpsFix = true;
        _latestReliablePotentialGpsFixAt = event.timestamp;
        _latestReliablePotentialSpeedMetersPerSecond =
            event.speedMetersPerSecond;

        if (_isActiveSpeed(event.speedMetersPerSecond)) {
          return _transitionTo(
            TrackingState.activeTracking,
            'gps_speed_above_active_threshold',
            event.timestamp,
          );
        }

        if (_isStationarySpeed(event.speedMetersPerSecond)) {
          _potentialStationaryGpsFixes += 1;

          if (_potentialStationaryGpsFixes >=
              config.requiredPotentialStationaryGpsFixes) {
            return _transitionTo(
              TrackingState.stationary,
              'gps_stationary_in_potential_motion',
              event.timestamp,
            );
          }
        } else {
          _potentialStationaryGpsFixes = 0;
        }

        return _stay(event.timestamp);
      case TrackingState.activeTracking:
        return _evaluateActiveStationaryEvidence(event.timestamp);
    }
  }

  FsmDecision _onPotentialMotionTimeout(
    PotentialMotionTimeoutElapsed event,
  ) {
    if (_state != TrackingState.potentialMotion) {
      return _stay(event.timestamp);
    }

    final hasGpsConfirmedMotion = _hasReliablePotentialGpsFix &&
        _isFreshGpsFix(_latestReliablePotentialGpsFixAt, event.timestamp) &&
        _isActiveSpeed(_latestReliablePotentialSpeedMetersPerSecond);
    final hasFallbackMotionWithoutReliableGps = !_hasReliablePotentialGpsFix &&
        _potentialMotionWindows >= config.requiredPotentialMotionWindows;
    final hasConfirmedMotion =
        hasGpsConfirmedMotion || hasFallbackMotionWithoutReliableGps;

    if (!hasConfirmedMotion) {
      return _transitionTo(
        TrackingState.stationary,
        'potential_motion_timeout_without_confirmed_trip',
        event.timestamp,
      );
    }

    return _transitionTo(
      TrackingState.activeTracking,
      hasGpsConfirmedMotion
          ? 'gps_speed_above_active_threshold'
          : 'motion_confirmed_without_reliable_gps',
      event.timestamp,
    );
  }

  FsmDecision _evaluateActiveStationaryEvidence(DateTime timestamp) {
    if (!_isStationarySpeed(_latestSpeedMetersPerSecond) ||
        _isMotion(_latestSigma)) {
      _stationaryEvidenceStartedAt = null;
      return _stay(timestamp);
    }

    _stationaryEvidenceStartedAt ??= timestamp;
    final stationaryDuration = timestamp.difference(
      _stationaryEvidenceStartedAt!,
    );

    if (stationaryDuration >= config.activeStationaryGracePeriod) {
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

    if (nextState == TrackingState.potentialMotion) {
      _resetPotentialEvidence();
    }

    if (nextState == TrackingState.stationary) {
      _stationaryStartedAt = timestamp;
      _consecutiveMotionWindows = 0;
      _resetPotentialEvidence();
      _resetStationaryGpsEvidence();
    } else {
      _stationaryStartedAt = null;
      _resetStationaryGpsEvidence();
    }

    if (nextState != TrackingState.activeTracking) {
      _stationaryEvidenceStartedAt = null;
    } else {
      _resetPotentialEvidence();
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
    if (_state != TrackingState.stationary) {
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

  bool _isActiveSpeed(double speedMetersPerSecond) {
    return speedMetersPerSecond > config.activeSpeedThresholdMetersPerSecond;
  }

  bool _isStationaryDirectActiveSpeed(double speedMetersPerSecond) {
    return speedMetersPerSecond >
        config.stationaryGpsActiveSpeedThresholdMetersPerSecond;
  }

  FsmDecision _onStationaryGpsFix(GpsFixReceived event) {
    if (!_isActiveSpeed(event.speedMetersPerSecond)) {
      _resetStationaryGpsEvidence();
      return _stay(event.timestamp);
    }

    final hasReliableGpsFix = _isReliableGpsFix(event);
    final hasFastSpeed =
        _isStationaryDirectActiveSpeed(event.speedMetersPerSecond);

    if (hasReliableGpsFix) {
      _stationaryReliableGpsMotionFixes += 1;
      _stationaryReliableGpsFastFixes =
          hasFastSpeed ? _stationaryReliableGpsFastFixes + 1 : 0;
      _stationaryUnreliableGpsMotionFixes = 0;
      _stationaryUnreliableGpsFastFixes = 0;

      if (_stationaryReliableGpsFastFixes >=
          config.requiredStationaryReliableGpsFastFixes) {
        return _transitionTo(
          TrackingState.activeTracking,
          'gps_reliable_fast_speed_confirmed_in_stationary',
          event.timestamp,
        );
      }

      if (_stationaryReliableGpsMotionFixes >=
          config.requiredStationaryReliableGpsMotionFixes) {
        return _transitionTo(
          TrackingState.potentialMotion,
          'gps_reliable_motion_confirmed_in_stationary',
          event.timestamp,
        );
      }

      return _stay(event.timestamp);
    }

    _stationaryUnreliableGpsMotionFixes += 1;
    _stationaryUnreliableGpsFastFixes =
        hasFastSpeed ? _stationaryUnreliableGpsFastFixes + 1 : 0;
    _stationaryReliableGpsMotionFixes = 0;
    _stationaryReliableGpsFastFixes = 0;

    if (_stationaryUnreliableGpsFastFixes >=
        config.requiredStationaryUnreliableGpsFastFixes) {
      return _transitionTo(
        TrackingState.activeTracking,
        'gps_unreliable_fast_speed_confirmed_in_stationary',
        event.timestamp,
      );
    }

    if (!hasFastSpeed &&
        _stationaryUnreliableGpsMotionFixes >=
            config.requiredStationaryUnreliableGpsMotionFixes) {
      return _transitionTo(
        TrackingState.potentialMotion,
        'gps_unreliable_motion_confirmed_in_stationary',
        event.timestamp,
      );
    }

    return _stay(event.timestamp);
  }

  bool _isStationarySpeed(double speedMetersPerSecond) {
    return speedMetersPerSecond <=
        config.stationarySpeedThresholdMetersPerSecond;
  }

  bool _isReliableGpsFix(GpsFixReceived event) {
    final accuracyMeters = event.accuracyMeters;
    return accuracyMeters == null ||
        accuracyMeters <= config.potentialGpsReliableAccuracyMeters;
  }

  bool _isFreshGpsFix(DateTime? fixTimestamp, DateTime now) {
    if (fixTimestamp == null) {
      return false;
    }
    return now.difference(fixTimestamp) <= config.gpsFixFreshness;
  }

  void _resetPotentialEvidence() {
    _potentialMotionWindows = 0;
    _potentialStationaryWindows = 0;
    _potentialStationaryGpsFixes = 0;
    _hasReliablePotentialGpsFix = false;
    _latestReliablePotentialSpeedMetersPerSecond = 0;
    _latestReliablePotentialGpsFixAt = null;
  }

  void _resetStationaryGpsEvidence() {
    _stationaryReliableGpsMotionFixes = 0;
    _stationaryReliableGpsFastFixes = 0;
    _stationaryUnreliableGpsMotionFixes = 0;
    _stationaryUnreliableGpsFastFixes = 0;
  }
}
