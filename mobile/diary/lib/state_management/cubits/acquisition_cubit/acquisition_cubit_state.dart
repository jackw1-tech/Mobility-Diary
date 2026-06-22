import 'package:diary/features/acquisition/domain/acquisition_domain.dart';
import 'package:latlong2/latlong.dart';

enum AcquisitionCubitStatus {
  idle,
  tracking,
}

class AcquisitionCubitState {
  final AcquisitionCubitStatus status;
  final AcquisitionSnapshot snapshot;
  final AcquisitionSyncSnapshot syncSnapshot;
  final List<AcquisitionMetricCluster> metricClusters;

  /// Percorso accumulato durante la sessione di tracking corrente, in ordine
  /// cronologico. Si svuota a ogni nuovo `startTracking`.
  final List<LatLng> routePoints;

  const AcquisitionCubitState({
    required this.status,
    required this.snapshot,
    this.syncSnapshot = const AcquisitionSyncSnapshot.none(),
    this.metricClusters = const [],
    this.routePoints = const [],
  });

  factory AcquisitionCubitState.initial() {
    return AcquisitionCubitState.fromSnapshot(AcquisitionSnapshot.idle());
  }

  factory AcquisitionCubitState.fromSnapshot(
    AcquisitionSnapshot snapshot, {
    AcquisitionSyncSnapshot syncSnapshot = const AcquisitionSyncSnapshot.none(),
    List<AcquisitionMetricCluster> metricClusters = const [],
    List<LatLng> routePoints = const [],
  }) {
    return AcquisitionCubitState(
      status: snapshot.isTracking
          ? AcquisitionCubitStatus.tracking
          : AcquisitionCubitStatus.idle,
      snapshot: snapshot,
      syncSnapshot: syncSnapshot,
      metricClusters: metricClusters,
      routePoints: routePoints,
    );
  }

  AcquisitionCubitState copyWith({
    AcquisitionCubitStatus? status,
    AcquisitionSnapshot? snapshot,
    AcquisitionSyncSnapshot? syncSnapshot,
    List<AcquisitionMetricCluster>? metricClusters,
    List<LatLng>? routePoints,
  }) {
    return AcquisitionCubitState(
      status: status ?? this.status,
      snapshot: snapshot ?? this.snapshot,
      syncSnapshot: syncSnapshot ?? this.syncSnapshot,
      metricClusters: metricClusters ?? this.metricClusters,
      routePoints: routePoints ?? this.routePoints,
    );
  }

  bool get isTracking => status == AcquisitionCubitStatus.tracking;

  /// Ultima posizione GPS nota (latest fix della sessione), se disponibile.
  LatLng? get latestPosition {
    if (!snapshot.hasPosition) return null;
    return LatLng(snapshot.latitude!, snapshot.longitude!);
  }

  TrackingState get trackingState => snapshot.trackingState;

  SamplingProfile get samplingProfile => snapshot.samplingProfile;

  double get latestSigma => snapshot.latestSigma;

  double get latestSpeedMetersPerSecond {
    return snapshot.latestSpeedMetersPerSecond;
  }
}

class AcquisitionMetricCluster {
  final DateTime startedAt;
  final int sampleCount;
  final double sigmaAverage;
  final double sigmaMin;
  final double sigmaMax;
  final double speedKmhAverage;
  final double speedKmhMin;
  final double speedKmhMax;

  const AcquisitionMetricCluster({
    required this.startedAt,
    required this.sampleCount,
    required this.sigmaAverage,
    required this.sigmaMin,
    required this.sigmaMax,
    required this.speedKmhAverage,
    required this.speedKmhMin,
    required this.speedKmhMax,
  });

  factory AcquisitionMetricCluster.fromSnapshot(
    AcquisitionSnapshot snapshot,
  ) {
    final speedKmh = snapshot.latestSpeedKilometersPerHour;
    return AcquisitionMetricCluster(
      startedAt: snapshot.updatedAt,
      sampleCount: 1,
      sigmaAverage: snapshot.latestSigma,
      sigmaMin: snapshot.latestSigma,
      sigmaMax: snapshot.latestSigma,
      speedKmhAverage: speedKmh,
      speedKmhMin: speedKmh,
      speedKmhMax: speedKmh,
    );
  }

  AcquisitionMetricCluster merge(AcquisitionSnapshot snapshot) {
    final nextCount = sampleCount + 1;
    final nextSigma = snapshot.latestSigma;
    final nextSpeedKmh = snapshot.latestSpeedKilometersPerHour;

    return AcquisitionMetricCluster(
      startedAt: startedAt,
      sampleCount: nextCount,
      sigmaAverage: ((sigmaAverage * sampleCount) + nextSigma) / nextCount,
      sigmaMin: nextSigma < sigmaMin ? nextSigma : sigmaMin,
      sigmaMax: nextSigma > sigmaMax ? nextSigma : sigmaMax,
      speedKmhAverage:
          ((speedKmhAverage * sampleCount) + nextSpeedKmh) / nextCount,
      speedKmhMin: nextSpeedKmh < speedKmhMin ? nextSpeedKmh : speedKmhMin,
      speedKmhMax: nextSpeedKmh > speedKmhMax ? nextSpeedKmh : speedKmhMax,
    );
  }
}
