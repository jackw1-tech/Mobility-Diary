import 'dart:convert';

import 'package:diary/model/entities/auth/auth_session.dart';
import 'package:diary/network/service/auth_session_store.dart';
import 'package:diary/model/entities/auth/auth_user.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureAuthSessionStore implements AuthSessionStore {
  static const tokenKey = 'auth.access_token';
  static const expiresAtKey = 'auth.expires_at';
  static const userKey = 'auth.user';

  final FlutterSecureStorage _storage;

  const SecureAuthSessionStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  @override
  Future<String?> readAccessToken() => _storage.read(key: tokenKey);

  @override
  Future<DateTime?> readExpiresAt() async {
    final raw = await _storage.read(key: expiresAtKey);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.parse(raw);
  }

  @override
  Future<void> saveSession(AuthSession session) async {
    await _storage.write(key: tokenKey, value: session.accessToken);
    await _storage.write(
      key: expiresAtKey,
      value: session.expiresAt.toIso8601String(),
    );
    await saveUser(session.user);
  }

  @override
  Future<void> saveUser(AuthUser user) async {
    await _storage.write(key: userKey, value: jsonEncode(user.toJson()));
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: tokenKey);
    await _storage.delete(key: expiresAtKey);
    await _storage.delete(key: userKey);
  }
}
