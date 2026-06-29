import 'package:diary/features/acquisition/device/device_identity_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeviceIdentityStore', () {
    test('reuses an existing stored device id', () async {
      final values = {
        DeviceIdentityStore.deviceIdKey: 'existing-device',
      };
      final store = _memoryStore(values);

      final deviceId = await store.getOrCreateDeviceId();

      expect(deviceId, 'existing-device');
      expect(values[DeviceIdentityStore.deviceIdKey], 'existing-device');
    });

    test('creates and stores a stable device id when missing', () async {
      final values = <String, String>{};
      final store = _memoryStore(values, createId: () => 'created-device');

      final first = await store.getOrCreateDeviceId();
      final second = await store.getOrCreateDeviceId();

      expect(first, 'created-device');
      expect(second, 'created-device');
      expect(values[DeviceIdentityStore.deviceIdKey], 'created-device');
    });
  });
}

DeviceIdentityStore _memoryStore(
  Map<String, String> values, {
  String Function()? createId,
}) {
  return DeviceIdentityStore.custom(
    read: (key) async => values[key],
    write: (key, value) async => values[key] = value,
    createId: createId,
  );
}
