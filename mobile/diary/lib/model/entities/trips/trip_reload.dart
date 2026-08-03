class TripReload {
  final int ingestionId;
  final int tripId;
  final String coreStatus;
  final String rawStatus;
  final int gpsPoints;
  final int stateTransitions;
  final int pathPoints;
  final double distanceMeters;
  final bool mapAvailable;

  const TripReload({
    required this.ingestionId,
    required this.tripId,
    required this.coreStatus,
    required this.rawStatus,
    required this.gpsPoints,
    required this.stateTransitions,
    required this.pathPoints,
    required this.distanceMeters,
    required this.mapAvailable,
  });
}

class TripReloadSlot {
  final DateTime startedAt;
  final DateTime endedAt;

  const TripReloadSlot({
    required this.startedAt,
    required this.endedAt,
  });
}

class TripReloadSlots {
  final int sourceTripId;
  final int durationSeconds;
  final List<TripReloadSlot> slots;

  const TripReloadSlots({
    required this.sourceTripId,
    required this.durationSeconds,
    required this.slots,
  });
}
