import 'tracking_state.dart';

enum GpsAccuracyProfile {
  lowPower,
  highAccuracy,
}

class SamplingProfile {
  final int accelerometerHz;
  final int gyroscopeHz;
  final int magnetometerHz;
  final bool gpsEnabled;
  final Duration? gpsInterval;
  final double? gpsDistanceFilterMeters;
  final GpsAccuracyProfile gpsAccuracy;
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
    required this.gpsAccuracy,
    required this.harWindowEnabled,
    required this.persistSensorWindows,
    required this.persistGpsPoints,
  });

  const SamplingProfile.stationary() : this.stationaryRecent();

  const SamplingProfile.stationaryRecent()
      : this(
          accelerometerHz: 10,
          gyroscopeHz: 0,
          magnetometerHz: 0,
          gpsEnabled: true,
          gpsInterval: const Duration(seconds: 20),
          gpsDistanceFilterMeters: 30,
          gpsAccuracy: GpsAccuracyProfile.highAccuracy,
          harWindowEnabled: false,
          persistSensorWindows: false,
          persistGpsPoints: true,
        );

  const SamplingProfile.stationaryDeep()
      : this(
          accelerometerHz: 10,
          gyroscopeHz: 0,
          magnetometerHz: 0,
          gpsEnabled: true,
          gpsInterval: const Duration(minutes: 3),
          gpsDistanceFilterMeters: 100,
          gpsAccuracy: GpsAccuracyProfile.lowPower,
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
          gpsAccuracy: GpsAccuracyProfile.highAccuracy,
          harWindowEnabled: true,
          persistSensorWindows: true,
          persistGpsPoints: true,
        );

  factory SamplingProfile.forState(
    TrackingState state, {
    bool stationaryDeep = false,
  }) {
    switch (state) {
      case TrackingState.stationary:
        return stationaryDeep
            ? const SamplingProfile.stationaryDeep()
            : const SamplingProfile.stationaryRecent();
      case TrackingState.movement:
        return const SamplingProfile.movement();
    }
  }
}
