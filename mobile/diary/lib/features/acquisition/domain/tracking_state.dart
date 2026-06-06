enum TrackingState {
  stationary,
  potentialMotion,
  activeTracking,
}

extension TrackingStateLabel on TrackingState {
  String get wireName {
    switch (this) {
      case TrackingState.stationary:
        return 'STATIONARY';
      case TrackingState.potentialMotion:
        return 'POTENTIAL_MOTION';
      case TrackingState.activeTracking:
        return 'ACTIVE_TRACKING';
    }
  }
}
