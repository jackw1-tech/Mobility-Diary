import 'package:diary/network/service/device_identity_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

typedef DeviceIdReader = Future<String?> Function(String key);
typedef DeviceIdWriter = Future<void> Function(String key, String value);

class SecureDeviceIdentityStore implements DeviceIdentityStore {
  static const deviceIdKey = 'acquisition.device_id';

  final DeviceIdReader _read;
  final DeviceIdWriter _write;
  final String Function() _createId;

  factory SecureDeviceIdentityStore({
    FlutterSecureStorage? storage,
    String Function()? createId,
  }) {
    final secureStorage = storage ?? const FlutterSecureStorage();
    return SecureDeviceIdentityStore.custom(
      read: (key) => secureStorage.read(key: key),
      write: (key, value) => secureStorage.write(key: key, value: value),
      createId: createId,
    );
  }

  const SecureDeviceIdentityStore.custom({
    required DeviceIdReader read,
    required DeviceIdWriter write,
    String Function()? createId,
  })  : _read = read,
        _write = write,
        _createId = createId ?? _defaultCreateId;

  @override
  Future<String> getOrCreateDeviceId() async {
    final existing = await _read(deviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final created = _createId();
    await _write(deviceIdKey, created);
    return created;
  }

  static String _defaultCreateId() => const Uuid().v4();
}
