import 'fsm_engine.dart';
import 'sampling_profile.dart';
import 'tracking_state.dart';

class AcquisitionSnapshot {
  final bool isTracking;
  final TrackingState trackingState;
  final SamplingProfile samplingProfile;
  final double latestSigma;
  final double latestSpeedMetersPerSecond;
  final FsmTransition? lastTransition;
  final DateTime updatedAt;

  /// Ultima posizione GPS nota durante la sessione corrente.
  /// `null` finché non arriva il primo fix (o quando non si sta tracciando).
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;

  /// Countdown dei secondi rimanenti alla fine della riproduzione live.
  /// `null` se non in replay o se mancano più di 15 secondi alla fine.
  final int? replaySecondsRemaining;

  const AcquisitionSnapshot({
    required this.isTracking,
    required this.trackingState,
    required this.samplingProfile,
    required this.latestSigma,
    required this.latestSpeedMetersPerSecond,
    required this.lastTransition,
    required this.updatedAt,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.replaySecondsRemaining,
  });

  factory AcquisitionSnapshot.idle({DateTime? updatedAt}) {
    return AcquisitionSnapshot(
      isTracking: false,
      trackingState: TrackingState.stationary,
      samplingProfile: const SamplingProfile.stationary(),
      latestSigma: 0,
      latestSpeedMetersPerSecond: 0,
      lastTransition: null,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
      replaySecondsRemaining: null,
    );
  }

  double get latestSpeedKilometersPerHour {
    return latestSpeedMetersPerSecond * 3.6;
  }

  bool get hasPosition => latitude != null && longitude != null;
}
