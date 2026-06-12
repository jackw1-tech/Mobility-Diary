import 'package:diary/features/auth/domain/auth_session.dart';
import 'package:diary/features/auth/domain/auth_user.dart';

abstract class AuthRepository {
  AuthUser? get currentUser;

  String? get accessToken;

  bool get isAuthenticated;

  Future<AuthSession?> restoreSession();

  Future<AuthSession> login({
    required String email,
    required String password,
  });

  Future<AuthSession> loginAsGuest();

  Future<AuthSession> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  });

  Future<AuthUser> loadCurrentUser();

  Future<void> logout();
}
