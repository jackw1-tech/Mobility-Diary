import 'package:diary/model/entities/acquisition/acquisition_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GpsFixReceived.fromPlatform', () {
    test('keeps zero and low platform speeds as valid stationary evidence', () {
      final event = GpsFixReceived.fromPlatform(
        timestamp: DateTime.utc(2026, 9, 4, 10),
        latitude: 45,
        longitude: 9,
        accuracyMeters: 5,
        platformSpeedMetersPerSecond: 0.2,
      );

      expect(event.speedMetersPerSecond, 0.2);
      expect(event.platformSpeedMetersPerSecond, 0.2);
      expect(event.hasUsableSpeed, isTrue);
    });

    test('marks invalid platform speeds as unavailable instead of zero', () {
      for (final invalidSpeed in [double.nan, double.infinity, -1.0, 81.0]) {
        final event = GpsFixReceived.fromPlatform(
          timestamp: DateTime.utc(2026, 9, 4, 10),
          latitude: 45,
          longitude: 9,
          accuracyMeters: 5,
          platformSpeedMetersPerSecond: invalidSpeed,
        );

        expect(event.speedMetersPerSecond, isNull);
        expect(event.hasUsableSpeed, isFalse);
      }
    });
  });
}
