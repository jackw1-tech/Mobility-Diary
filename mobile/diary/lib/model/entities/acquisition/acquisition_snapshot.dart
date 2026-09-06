import 'fsm_engine.dart';
import 'tracking_state.dart';

// Fotografia dello stato corrente dell'acquisizione dei dati, descrive ciò che il sistema ha capito dall'ultima misurazione
// e come si sta comportando ora
class AcquisitionSnapshot {
  final bool isTracking;
  final TrackingState trackingState;
  final double latestSigma;
  final double latestSpeedMetersPerSecond;
  final DateTime? latestSigmaAt;
  final DateTime? latestSpeedAt;
  // Diagnostica: ogni singola callback grezza dell'accelerometro, non solo
  // quelle che completano una finestra. Serve a distinguere "l'OS ha smesso
  // di consegnare eventi" (es. app in background) da "gli eventi arrivano ma
  // la finestra non si completa".
  final int rawAccelerometerEventCount;
  final DateTime? latestRawAccelerometerEventAt;
  // Stessa idea: totali assoluti dal runtime, non "quante volte la UI si e'
  // ridisegnata" — cosi' non si perdono conteggi se la UI salta dei frame.
  final int completedSigmaWindowCount;
  final int gpsFixCount;
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
    required this.latestSigma,
    required this.latestSpeedMetersPerSecond,
    this.latestSigmaAt,
    this.latestSpeedAt,
    this.rawAccelerometerEventCount = 0,
    this.latestRawAccelerometerEventAt,
    this.completedSigmaWindowCount = 0,
    this.gpsFixCount = 0,
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
      latestSigma: 0,
      latestSpeedMetersPerSecond: 0,
      lastTransition: null,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
      replaySecondsRemaining: null,
    );
  }

  AcquisitionSnapshot copyWith({
    bool? isTracking,
    TrackingState? trackingState,
    double? latestSigma,
    double? latestSpeedMetersPerSecond,
    DateTime? latestSigmaAt,
    DateTime? latestSpeedAt,
    int? rawAccelerometerEventCount,
    DateTime? latestRawAccelerometerEventAt,
    int? completedSigmaWindowCount,
    int? gpsFixCount,
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
      latestSigma: latestSigma ?? this.latestSigma,
      latestSpeedMetersPerSecond:
          latestSpeedMetersPerSecond ?? this.latestSpeedMetersPerSecond,
      latestSigmaAt: latestSigmaAt ?? this.latestSigmaAt,
      latestSpeedAt: latestSpeedAt ?? this.latestSpeedAt,
      rawAccelerometerEventCount:
          rawAccelerometerEventCount ?? this.rawAccelerometerEventCount,
      latestRawAccelerometerEventAt:
          latestRawAccelerometerEventAt ?? this.latestRawAccelerometerEventAt,
      completedSigmaWindowCount:
          completedSigmaWindowCount ?? this.completedSigmaWindowCount,
      gpsFixCount: gpsFixCount ?? this.gpsFixCount,
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
