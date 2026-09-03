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

  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;

  final int? replaySecondsRemaining;
  final bool isReplay;

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
    this.isReplay = false,
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

  AcquisitionSnapshot copyWith({
    bool? isTracking,
    TrackingState? trackingState,
    SamplingProfile? samplingProfile,
    double? latestSigma,
    double? latestSpeedMetersPerSecond,
    FsmTransition? lastTransition,
    DateTime? updatedAt,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    int? replaySecondsRemaining,
    bool? isReplay,
  }) {
    return AcquisitionSnapshot(
      isTracking: isTracking ?? this.isTracking,
      trackingState: trackingState ?? this.trackingState,
      samplingProfile: samplingProfile ?? this.samplingProfile,
      latestSigma: latestSigma ?? this.latestSigma,
      latestSpeedMetersPerSecond:
          latestSpeedMetersPerSecond ?? this.latestSpeedMetersPerSecond,
      lastTransition: lastTransition == null && this.lastTransition == null
          ? null
          : (lastTransition ?? this.lastTransition),
      updatedAt: updatedAt ?? this.updatedAt,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
      replaySecondsRemaining:
          replaySecondsRemaining ?? this.replaySecondsRemaining,
      isReplay: isReplay ?? this.isReplay,
    );
  }

  bool get hasPosition => latitude != null && longitude != null;
}
