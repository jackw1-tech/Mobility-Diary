/// Dati sorgente di un viaggio da rigiocare, come li restituisce
/// GET /mobility/trips/reloadable/{id}/replay-data (schema ReplayDataOut).
class ReplayDataDto {
  final int sourceTripId;
  final List<ReplayGpsPointDto> gpsPoints;
  final List<ReplayStateTransitionDto> stateTransitions;

  const ReplayDataDto({
    required this.sourceTripId,
    required this.gpsPoints,
    required this.stateTransitions,
  });

  factory ReplayDataDto.fromJson(Map<String, dynamic> json) {
    return ReplayDataDto(
      sourceTripId: json['source_trip_id'] as int? ?? 0,
      gpsPoints: (json['gps_points'] as List<dynamic>? ?? const [])
          .map((value) => ReplayGpsPointDto.fromJson(
                Map<String, dynamic>.from(value as Map<dynamic, dynamic>),
              ))
          .toList(growable: false),
      stateTransitions:
          (json['state_transitions'] as List<dynamic>? ?? const [])
              .map((value) => ReplayStateTransitionDto.fromJson(
                    Map<String, dynamic>.from(value as Map<dynamic, dynamic>),
                  ))
              .toList(growable: false),
    );
  }
}

/// Schema ReplayPointOut.
class ReplayGpsPointDto {
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double speedMps;
  final double? accuracyMeters;

  const ReplayGpsPointDto({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.speedMps,
    this.accuracyMeters,
  });

  factory ReplayGpsPointDto.fromJson(Map<String, dynamic> json) {
    return ReplayGpsPointDto(
      timestamp: DateTime.parse(json['timestamp'] as String).toUtc(),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      speedMps: (json['speed_mps'] as num?)?.toDouble() ?? 0,
      accuracyMeters: (json['accuracy_meters'] as num?)?.toDouble(),
    );
  }
}

/// Schema ReplayTransitionOut. Il backend non restituisce reason/sigma/speed:
/// una transizione rigiocata non porta con se' le evidenze dell'originale.
class ReplayStateTransitionDto {
  final DateTime timestamp;
  final String fromState;
  final String toState;

  const ReplayStateTransitionDto({
    required this.timestamp,
    required this.fromState,
    required this.toState,
  });

  factory ReplayStateTransitionDto.fromJson(Map<String, dynamic> json) {
    return ReplayStateTransitionDto(
      timestamp: DateTime.parse(json['timestamp'] as String).toUtc(),
      fromState: json['from_state'] as String? ?? '',
      toState: json['to_state'] as String? ?? '',
    );
  }
}
