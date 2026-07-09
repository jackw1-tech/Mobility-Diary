import 'package:diary/features/acquisition/runtime/acquisition_sensor_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  group('canStartAcquisitionLocationStream', () {
    test('allows foreground GPS when permission is whileInUse', () {
      expect(
        canStartAcquisitionLocationStream(LocationPermission.whileInUse),
        isTrue,
      );
    });

    test('allows background-capable GPS when permission is always', () {
      expect(
        canStartAcquisitionLocationStream(LocationPermission.always),
        isTrue,
      );
    });

    test('rejects denied permissions', () {
      expect(
        canStartAcquisitionLocationStream(LocationPermission.denied),
        isFalse,
      );
      expect(
        canStartAcquisitionLocationStream(LocationPermission.deniedForever),
        isFalse,
      );
    });
  });
}
