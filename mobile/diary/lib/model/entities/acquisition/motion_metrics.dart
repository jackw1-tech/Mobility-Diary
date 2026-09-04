import 'dart:math';

class AccelerationSample {
  final double x;
  final double y;
  final double z;

  const AccelerationSample({
    required this.x,
    required this.y,
    required this.z,
  });
}

class MotionMetrics {
  const MotionMetrics._();

  // Magnitudo del vettore di accelerazione: SVM
  static double signalVectorMagnitude(AccelerationSample sample) {
    return sqrt(
      sample.x * sample.x + sample.y * sample.y + sample.z * sample.z,
    );
  }

  static double standardDeviation(List<double> values) {
    if (values.isEmpty) {
      return 0;
    }

    final mean = values.reduce((left, right) => left + right) / values.length;
    final variance = values.map((value) {
          final delta = value - mean;
          return delta * delta;
        }).reduce((left, right) => left + right) /
        values.length;

    return sqrt(variance);
  }

  static double accelerationMagnitudeSigma(
    List<AccelerationSample> samples,
  ) {
    final magnitudes = samples.map(signalVectorMagnitude).toList();
    return standardDeviation(magnitudes);
  }
}
