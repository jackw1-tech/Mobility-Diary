import 'package:diary/features/acquisition/runtime/gps_speed_estimator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GpsSpeedEstimator', () {
    test('uses platform speed when it is available and reasonable', () {
      final estimator = GpsSpeedEstimator();

      final speed = estimator.add(
        GpsSpeedFix(
          timestamp: DateTime.utc(2026),
          latitude: 44.49491,
          longitude: 11.34261,
          accuracyMeters: 8,
          platformSpeedMetersPerSecond: 12,
        ),
      );

      expect(speed, 12);
    });

    test('falls back to distance over time when platform speed is zero', () {
      final estimator = GpsSpeedEstimator();
      final now = DateTime.utc(2026);

      estimator.add(
        GpsSpeedFix(
          timestamp: now,
          latitude: 44.49491,
          longitude: 11.34261,
          accuracyMeters: 8,
          platformSpeedMetersPerSecond: 0,
        ),
      );
      final speed = estimator.add(
        GpsSpeedFix(
          timestamp: now.add(const Duration(seconds: 10)),
          latitude: 44.49491,
          longitude: 11.34400,
          accuracyMeters: 8,
          platformSpeedMetersPerSecond: 0,
        ),
      );

      expect(speed, greaterThan(10));
    });

    test('keeps GPS jitter inside the accuracy dead zone at zero speed', () {
      final estimator = GpsSpeedEstimator();
      final now = DateTime.utc(2026);

      estimator.add(
        GpsSpeedFix(
          timestamp: now,
          latitude: 44.49491,
          longitude: 11.34261,
          accuracyMeters: 25,
          platformSpeedMetersPerSecond: 0,
        ),
      );
      final speed = estimator.add(
        GpsSpeedFix(
          timestamp: now.add(const Duration(seconds: 10)),
          latitude: 44.49492,
          longitude: 11.34262,
          accuracyMeters: 25,
          platformSpeedMetersPerSecond: 0,
        ),
      );

      expect(speed, 0);
    });

    test('ignores small platform speed reports below the usable threshold',
        () {
      final estimator = GpsSpeedEstimator();
      final now = DateTime.utc(2026);

      // Rumore Doppler/multipath tipico da fermo (es. indoor): una velocita'
      // di piattaforma piccola ma diversa da zero non deve passare cosi'
      // com'e', e senza un vero spostamento anche il fallback a distanza
      // resta sotto la dead zone.
      estimator.add(
        GpsSpeedFix(
          timestamp: now,
          latitude: 44.49491,
          longitude: 11.34261,
          accuracyMeters: 8,
          platformSpeedMetersPerSecond: 0.3,
        ),
      );
      final speed = estimator.add(
        GpsSpeedFix(
          timestamp: now.add(const Duration(seconds: 10)),
          latitude: 44.49491,
          longitude: 11.34261,
          accuracyMeters: 8,
          platformSpeedMetersPerSecond: 0.3,
        ),
      );

      expect(speed, 0);
    });

    test('ignores impossible speed spikes', () {
      final estimator = GpsSpeedEstimator();
      final now = DateTime.utc(2026);

      estimator.add(
        GpsSpeedFix(
          timestamp: now,
          latitude: 44.49491,
          longitude: 11.34261,
          accuracyMeters: 8,
          platformSpeedMetersPerSecond: 0,
        ),
      );
      final speed = estimator.add(
        GpsSpeedFix(
          timestamp: now.add(const Duration(seconds: 1)),
          latitude: 45.49491,
          longitude: 12.34261,
          accuracyMeters: 8,
          platformSpeedMetersPerSecond: 0,
        ),
      );

      expect(speed, 0);
    });
  });
}
