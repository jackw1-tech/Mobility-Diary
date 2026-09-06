import 'tracking_state.dart';

class SamplingProfile {
  final int accelerometerHz;
  final int gyroscopeHz;
  final double?
      gpsDistanceFilterMeters; // Non darmi un punto se non mi sono spostato di almeno X metri dall'ultimo punto
  // In stationary i dati dei sensori vengono solo usati per capire se sono
  // ancora fermo: non viene costruita la finestra 500x6 e quindi non c'e'
  // nulla da salvare per la classificazione HAR.
  final bool harWindowEnabled;

  const SamplingProfile({
    required this.accelerometerHz,
    required this.gyroscopeHz,
    required this.gpsDistanceFilterMeters,
    required this.harWindowEnabled,
  });

  const SamplingProfile.stationary()
      : this(
          accelerometerHz: 10,
          gyroscopeHz: 0,
          gpsDistanceFilterMeters: 3,
          harWindowEnabled: false,
        );

  const SamplingProfile.movement()
      : this(
          accelerometerHz: 100,
          gyroscopeHz: 100,
          gpsDistanceFilterMeters: 3,
          harWindowEnabled: true,
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
