import 'package:diary/features/auth/domain/auth_session.dart';
import 'package:diary/features/auth/domain/auth_user.dart';

abstract class AuthSessionStore {
  Future<String?> readAccessToken();

  Future<DateTime?> readExpiresAt();

  Future<void> saveSession(AuthSession session);

  Future<void> saveUser(AuthUser user);

  Future<void> clear();
}
