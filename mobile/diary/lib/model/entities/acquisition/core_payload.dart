class CoreGpsPoint {
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double? speedMps;
  final double? accuracyMeters;

  const CoreGpsPoint({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.speedMps,
    this.accuracyMeters,
  });

  CoreGpsPoint shiftedBy(Duration offset) => CoreGpsPoint(
        timestamp: timestamp.add(offset),
        latitude: latitude,
        longitude: longitude,
        speedMps: speedMps,
        accuracyMeters: accuracyMeters,
      );
}

class CoreStateTransition {
  final DateTime timestamp;
  final String fromState;
  final String toState;

  final double? sigma;
  final double? speedMps;

  const CoreStateTransition({
    required this.timestamp,
    required this.fromState,
    required this.toState,
    this.sigma,
    this.speedMps,
  });

  CoreStateTransition shiftedBy(Duration offset) => CoreStateTransition(
        timestamp: timestamp.add(offset),
        fromState: fromState,
        toState: toState,
        sigma: sigma,
        speedMps: speedMps,
      );
}

class ReplaySource {
  final int sourceTripId;
  final List<CoreGpsPoint> points;
  final List<CoreStateTransition> transitions;

  const ReplaySource({
    required this.sourceTripId,
    required this.points,
    required this.transitions,
  });

  bool get isEmpty => points.isEmpty && transitions.isEmpty;
}
