import 'package:diary/features/acquisition/domain/acquisition_domain.dart';

enum AcquisitionCubitStatus {
  idle,
  tracking,
}

class AcquisitionCubitState {
  final AcquisitionCubitStatus status;
  final AcquisitionSnapshot snapshot;
  final List<AcquisitionMetricCluster> metricClusters;

  const AcquisitionCubitState({
    required this.status,
    required this.snapshot,
    this.metricClusters = const [],
  });

  factory AcquisitionCubitState.initial() {
    return AcquisitionCubitState.fromSnapshot(AcquisitionSnapshot.idle());
  }

  factory AcquisitionCubitState.fromSnapshot(
    AcquisitionSnapshot snapshot, {
    List<AcquisitionMetricCluster> metricClusters = const [],
  }) {
    return AcquisitionCubitState(
      status: snapshot.isTracking
          ? AcquisitionCubitStatus.tracking
          : AcquisitionCubitStatus.idle,
      snapshot: snapshot,
      metricClusters: metricClusters,
    );
  }

  bool get isTracking => status == AcquisitionCubitStatus.tracking;

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
