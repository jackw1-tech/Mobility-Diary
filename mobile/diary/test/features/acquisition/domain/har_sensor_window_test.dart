import 'package:diary/features/acquisition/domain/acquisition_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HarSensorWindow', () {
    test('normalizes raw samples to the 500 x 6 model shape', () {
      final window = HarSensorWindow(
        startedAt: DateTime.utc(2026, 1, 1),
        endedAt: DateTime.utc(2026, 1, 1, 0, 0, 5),
        accelerometerHz: 100,
        gyroscopeHz: 100,
        magnetometerHz: 0,
        samples: [
          _sample(value: 0),
          _sample(value: 10),
        ],
      );

      final modelInput = window.modelInputMatrix;

      expect(window.hasTargetSamplingRate, isTrue);
      expect(window.hasTargetShape, isTrue);
      expect(modelInput, hasLength(500));
      expect(modelInput.first, hasLength(6));
      expect(modelInput.first, List<double>.filled(6, 0));
      expect(modelInput.last, List<double>.filled(6, 10));
    });
  });
}

HarSensorSample _sample({required double value}) {
  return HarSensorSample(
    timestamp: DateTime.utc(2026, 1, 1),
    accX: value,
    accY: value,
    accZ: value,
    gyrX: value,
    gyrY: value,
    gyrZ: value,
  );
}
