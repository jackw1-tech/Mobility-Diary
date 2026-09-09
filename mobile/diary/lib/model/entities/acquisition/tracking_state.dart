enum TrackingState {
  stationary,
  movement;

  static TrackingState fromWire(String? wireName) => wireName == 'MOVEMENT'
      ? TrackingState.movement
      : TrackingState.stationary;
}

extension TrackingStateLabel on TrackingState {
  String get wireName {
    switch (this) {
      case TrackingState.stationary:
        return 'STATIONARY';
      case TrackingState.movement:
        return 'MOVEMENT';
    }
  }
}
