sealed class TrackingEvent {
  final DateTime timestamp;

  const TrackingEvent({required this.timestamp});
}

final class MotionWindowEvaluated extends TrackingEvent {
  final double sigma;
  final int sampleCount;

  const MotionWindowEvaluated({
    required super.timestamp,
    required this.sigma,
    required this.sampleCount,
  });
}

final class GpsFixReceived extends TrackingEvent {
  final double? latitude;
  final double? longitude;
  final double speedMetersPerSecond;
  final double? accuracyMeters;

  const GpsFixReceived({
    required super.timestamp,
    required this.speedMetersPerSecond,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
  });
}
