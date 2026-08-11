enum TrackingState {
  stationary,
  movement;

  /// Ricostruisce lo stato dal nome usato sul wire (DB locale/backend).
  /// Qualunque valore diverso da 'MOVEMENT' (incluso null) e' trattato come
  /// stationary, lo stato di riposo di default.
  static TrackingState fromWire(String? wireName) =>
      wireName == 'MOVEMENT' ? TrackingState.movement : TrackingState.stationary;
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
