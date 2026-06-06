import 'sampling_profile.dart';
import 'tracking_event.dart';
import 'tracking_state.dart';

class FsmConfig {
  final double movementSigmaThreshold;
  final int requiredMotionWindows;
  final int requiredPotentialMotionWindows;
  final int requiredPotentialStationaryWindows;
  final double activeSpeedThresholdMetersPerSecond;
  final double stationarySpeedThresholdMetersPerSecond;
  final Duration potentialMotionTimeout;
  final Duration activeStationaryGracePeriod;

  const FsmConfig({
    this.movementSigmaThreshold = 1,
    this.requiredMotionWindows = 4,
    this.requiredPotentialMotionWindows = 4,
    this.requiredPotentialStationaryWindows = 4,
    this.activeSpeedThresholdMetersPerSecond = 2 / 3.6,
    this.stationarySpeedThresholdMetersPerSecond = 0.1,
    this.potentialMotionTimeout = const Duration(seconds: 60),
    this.activeStationaryGracePeriod = const Duration(minutes: 2),
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
  double _latestSigma = 0;
  double _latestSpeedMetersPerSecond = 0;
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
        return _stay();
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

        if (_potentialMotionWindows >= config.requiredPotentialMotionWindows) {
          return _transitionTo(
            TrackingState.activeTracking,
            'sustained_motion_without_gps_speed',
            event.timestamp,
          );
        }

        return _stay();
      case TrackingState.activeTracking:
        return _evaluateActiveStationaryEvidence(event.timestamp);
    }
  }

  FsmDecision _onGpsFix(GpsFixReceived event) {
    _latestSpeedMetersPerSecond = event.speedMetersPerSecond;

    switch (_state) {
      case TrackingState.stationary:
        return _stay();
      case TrackingState.potentialMotion:
        if (_isActiveSpeed(event.speedMetersPerSecond)) {
          return _transitionTo(
            TrackingState.activeTracking,
            'gps_speed_above_active_threshold',
            event.timestamp,
          );
        }
        return _stay();
      case TrackingState.activeTracking:
        return _evaluateActiveStationaryEvidence(event.timestamp);
    }
  }

  FsmDecision _onPotentialMotionTimeout(
    PotentialMotionTimeoutElapsed event,
  ) {
    if (_state != TrackingState.potentialMotion) {
      return _stay();
    }

    final hasConfirmedMotion = _isActiveSpeed(_latestSpeedMetersPerSecond) ||
        _potentialMotionWindows >= config.requiredPotentialMotionWindows;

    if (!hasConfirmedMotion) {
      return _transitionTo(
        TrackingState.stationary,
        'potential_motion_timeout_without_confirmed_trip',
        event.timestamp,
      );
    }

    return _transitionTo(
      TrackingState.activeTracking,
      'motion_confirmed_without_gps_speed',
      event.timestamp,
    );
  }

  FsmDecision _evaluateActiveStationaryEvidence(DateTime timestamp) {
    if (!_isStationarySpeed(_latestSpeedMetersPerSecond) ||
        _isMotion(_latestSigma)) {
      _stationaryEvidenceStartedAt = null;
      return _stay();
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

    return _stay();
  }

  FsmDecision _transitionTo(
    TrackingState nextState,
    String reason,
    DateTime timestamp,
  ) {
    final previousState = _state;
    _state = nextState;

    if (nextState == TrackingState.potentialMotion) {
      _potentialMotionWindows = 0;
      _potentialStationaryWindows = 0;
    }

    if (nextState == TrackingState.stationary) {
      _consecutiveMotionWindows = 0;
      _potentialMotionWindows = 0;
      _potentialStationaryWindows = 0;
    }

    if (nextState != TrackingState.activeTracking) {
      _stationaryEvidenceStartedAt = null;
    } else {
      _potentialMotionWindows = 0;
      _potentialStationaryWindows = 0;
    }

    return FsmDecision(
      state: _state,
      samplingProfile: SamplingProfile.forState(_state),
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
      samplingProfile: SamplingProfile.forState(_state),
    );
  }

  bool _isMotion(double sigma) => sigma > config.movementSigmaThreshold;

  bool _isActiveSpeed(double speedMetersPerSecond) {
    return speedMetersPerSecond > config.activeSpeedThresholdMetersPerSecond;
  }

  bool _isStationarySpeed(double speedMetersPerSecond) {
    return speedMetersPerSecond <=
        config.stationarySpeedThresholdMetersPerSecond;
  }
}
