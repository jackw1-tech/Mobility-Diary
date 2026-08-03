enum TrackingState {
  stationary,
  movement,
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
