import 'package:diary/network/service/impl/gps_speed_estimator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('estimates movement from coordinates when platform speed is missing',
      () {
    final estimator = GpsSpeedEstimator();
    final startedAt = DateTime.utc(2026, 9, 4, 10);

    final first = estimator.add(
      GpsSpeedFix(
        timestamp: startedAt,
        latitude: 45.4642,
        longitude: 9.1900,
        accuracyMeters: 5,
        platformSpeedMetersPerSecond: -1,
      ),
    );
    final second = estimator.add(
      GpsSpeedFix(
        timestamp: startedAt.add(const Duration(seconds: 10)),
        latitude: 45.4652,
        longitude: 9.1900,
        accuracyMeters: 5,
        platformSpeedMetersPerSecond: -1,
      ),
    );

    expect(first, isNull);
    expect(second, greaterThan(10));
  });

  test('keeps a valid platform speed without coordinate fallback', () {
    final speed = GpsSpeedEstimator().add(
      GpsSpeedFix(
        timestamp: DateTime.utc(2026, 9, 4, 10),
        latitude: 45.4642,
        longitude: 9.1900,
        accuracyMeters: 5,
        platformSpeedMetersPerSecond: 0.2,
      ),
    );

    expect(speed, 0.2);
  });
}
