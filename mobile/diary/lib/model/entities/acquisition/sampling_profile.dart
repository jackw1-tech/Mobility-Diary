import 'tracking_state.dart';

class SamplingProfile {
  final int accelerometerHz;
  final int gyroscopeHz;
  final int magnetometerHz;
  final bool gpsEnabled;
  final Duration? gpsInterval;
  final double? gpsDistanceFilterMeters;
  final bool harWindowEnabled;
  final bool persistSensorWindows;
  final bool persistGpsPoints;

  const SamplingProfile({
    required this.accelerometerHz,
    required this.gyroscopeHz,
    required this.magnetometerHz,
    required this.gpsEnabled,
    required this.gpsInterval,
    required this.gpsDistanceFilterMeters,
    required this.harWindowEnabled,
    required this.persistSensorWindows,
    required this.persistGpsPoints,
  });

  const SamplingProfile.stationary()
      : this(
          accelerometerHz: 10,
          gyroscopeHz: 0,
          magnetometerHz: 0,
          gpsEnabled: true,
          gpsInterval: const Duration(seconds: 5),
          gpsDistanceFilterMeters: 3,
          harWindowEnabled: false,
          persistSensorWindows: false,
          persistGpsPoints: true,
        );

  const SamplingProfile.movement()
      : this(
          accelerometerHz: 100,
          gyroscopeHz: 100,
          magnetometerHz: 0,
          gpsEnabled: true,
          gpsInterval: const Duration(seconds: 2),
          gpsDistanceFilterMeters: 3,
          harWindowEnabled: true,
          persistSensorWindows: true,
          persistGpsPoints: true,
        );

  // Stato FSM -> traduzione -> SamplingProfile
  factory SamplingProfile.forState(TrackingState state) {
    switch (state) {
      case TrackingState.stationary:
        return const SamplingProfile.stationary();
      case TrackingState.movement:
        return const SamplingProfile.movement();
    }
  }
}
