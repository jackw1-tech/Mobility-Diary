import 'package:diary/network/service/device_identity_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Identita' del dispositivo
class SecureDeviceIdentityStore implements DeviceIdentityStore {
  static const deviceIdKey = 'acquisition.device_id';

  final FlutterSecureStorage _storage;

  const SecureDeviceIdentityStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  @override
  Future<String> getOrCreateDeviceId() async {
    final existing = await _storage.read(key: deviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final created = const Uuid().v4();
    await _storage.write(key: deviceIdKey, value: created);
    return created;
  }
}
