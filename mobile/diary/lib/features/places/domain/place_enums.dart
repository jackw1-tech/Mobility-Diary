enum PlaceReviewState {
  candidate('CANDIDATE'),
  confirmed('CONFIRMED'),
  rejected('REJECTED'),
  unknown('');

  final String wireName;

  const PlaceReviewState(this.wireName);

  static PlaceReviewState fromWire(String value) {
    for (final state in PlaceReviewState.values) {
      if (state.wireName == value) return state;
    }
    return PlaceReviewState.unknown;
  }
}

enum PlaceMiningState {
  idle('IDLE'),
  pending('PENDING'),
  running('RUNNING'),
  succeeded('SUCCEEDED'),
  failed('FAILED'),
  unknown('');

  final String wireName;

  const PlaceMiningState(this.wireName);

  static PlaceMiningState fromWire(String value) {
    for (final state in PlaceMiningState.values) {
      if (state.wireName == value) return state;
    }
    return PlaceMiningState.unknown;
  }
}
