sealed class TrackingEvent {
  final DateTime timestamp;

  const TrackingEvent({required this.timestamp});
}

final class MotionWindowEvaluated extends TrackingEvent {
  final double sigma;

  const MotionWindowEvaluated({
    required super.timestamp,
    required this.sigma,
  });
}

final class GpsFixReceived extends TrackingEvent {
  static const double _maximumReasonableSpeedMetersPerSecond = 80;

  final double? latitude;
  final double? longitude;
  final double? speedMetersPerSecond;
  final double? platformSpeedMetersPerSecond;
  final double? accuracyMeters;

  const GpsFixReceived({
    required super.timestamp,
    required this.speedMetersPerSecond,
    double? platformSpeedMetersPerSecond,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
  }) : platformSpeedMetersPerSecond =
            platformSpeedMetersPerSecond ?? speedMetersPerSecond;

  factory GpsFixReceived.fromPlatform({
    required DateTime timestamp,
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    required double platformSpeedMetersPerSecond,
  }) {
    final speedIsUsable = platformSpeedMetersPerSecond.isFinite &&
        platformSpeedMetersPerSecond >= 0 &&
        platformSpeedMetersPerSecond <= _maximumReasonableSpeedMetersPerSecond;
    return GpsFixReceived(
      timestamp: timestamp,
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
      platformSpeedMetersPerSecond: platformSpeedMetersPerSecond.isFinite
          ? platformSpeedMetersPerSecond
          : null,
      speedMetersPerSecond: speedIsUsable ? platformSpeedMetersPerSecond : null,
    );
  }

  bool get hasUsableSpeed => speedMetersPerSecond != null;
}
