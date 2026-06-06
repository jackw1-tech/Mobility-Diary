import 'tracking_state.dart';

class SamplingProfile {
  final int accelerometerHz;
  final int gyroscopeHz;
  final bool gpsEnabled;
  final Duration? gpsInterval;
  final double? gpsDistanceFilterMeters;
  final bool persistSensorWindows;
  final bool persistGpsPoints;

  const SamplingProfile({
    required this.accelerometerHz,
    required this.gyroscopeHz,
    required this.gpsEnabled,
    required this.gpsInterval,
    required this.gpsDistanceFilterMeters,
    required this.persistSensorWindows,
    required this.persistGpsPoints,
  });

  const SamplingProfile.stationary()
      : this(
          accelerometerHz: 10,
          gyroscopeHz: 0,
          gpsEnabled: false,
          gpsInterval: null,
          gpsDistanceFilterMeters: null,
          persistSensorWindows: false,
          persistGpsPoints: false,
        );

  const SamplingProfile.potentialMotion()
      : this(
          accelerometerHz: 50,
          gyroscopeHz: 50,
          gpsEnabled: true,
          gpsInterval: const Duration(seconds: 5),
          gpsDistanceFilterMeters: null,
          persistSensorWindows: false,
          persistGpsPoints: false,
        );

  const SamplingProfile.activeTracking()
      : this(
          accelerometerHz: 50,
          gyroscopeHz: 50,
          gpsEnabled: true,
          gpsInterval: const Duration(seconds: 2),
          gpsDistanceFilterMeters: 3,
          persistSensorWindows: true,
          persistGpsPoints: true,
        );

  factory SamplingProfile.forState(TrackingState state) {
    switch (state) {
      case TrackingState.stationary:
        return const SamplingProfile.stationary();
      case TrackingState.potentialMotion:
        return const SamplingProfile.potentialMotion();
      case TrackingState.activeTracking:
        return const SamplingProfile.activeTracking();
    }
  }
}
