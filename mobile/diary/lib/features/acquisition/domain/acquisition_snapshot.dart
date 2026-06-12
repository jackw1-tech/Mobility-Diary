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

  const AcquisitionSnapshot({
    required this.isTracking,
    required this.trackingState,
    required this.samplingProfile,
    required this.latestSigma,
    required this.latestSpeedMetersPerSecond,
    required this.lastTransition,
    required this.updatedAt,
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
    );
  }

  double get latestSpeedKilometersPerHour {
    return latestSpeedMetersPerSecond * 3.6;
  }
}
