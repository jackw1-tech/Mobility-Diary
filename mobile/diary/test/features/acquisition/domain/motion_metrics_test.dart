import 'package:diary/features/acquisition/domain/acquisition_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MotionMetrics', () {
    test('computes signal vector magnitude', () {
      const sample = AccelerationSample(x: 3, y: 4, z: 12);

      expect(MotionMetrics.signalVectorMagnitude(sample), 13);
    });

    test('computes acceleration magnitude sigma', () {
      const samples = [
        AccelerationSample(x: 0, y: 0, z: 9),
        AccelerationSample(x: 0, y: 0, z: 10),
        AccelerationSample(x: 0, y: 0, z: 11),
      ];

      expect(
        MotionMetrics.accelerationMagnitudeSigma(samples),
        closeTo(0.816, 0.001),
      );
    });

    test('returns zero for empty windows', () {
      expect(MotionMetrics.standardDeviation(const []), 0);
    });
  });
}
