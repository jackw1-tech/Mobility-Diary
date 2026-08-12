/// Contenuto del payload "core" di un viaggio: la traccia GPS e le transizioni
/// FSM. Ci arrivano per due strade — dal DB locale per un viaggio registrato
/// dal vivo, dal backend per un viaggio rigiocato — e da entrambe escono con
/// la stessa forma verso POST /ingestion/core-inline.

class CoreGpsPoint {
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double speedMps;
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
  final String reason;

  /// Evidenze della decisione FSM. Nulle per i viaggi rigiocati: il backend
  /// non restituisce le evidenze originali insieme alla transizione.
  final double? sigma;
  final double? speedMps;

  const CoreStateTransition({
    required this.timestamp,
    required this.fromState,
    required this.toState,
    this.reason = '',
    this.sigma,
    this.speedMps,
  });

  CoreStateTransition shiftedBy(Duration offset) => CoreStateTransition(
        timestamp: timestamp.add(offset),
        fromState: fromState,
        toState: toState,
        reason: reason,
        sigma: sigma,
        speedMps: speedMps,
      );
}

/// Traccia sorgente di un viaggio da rigiocare, gia' ordinata per timestamp.
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
