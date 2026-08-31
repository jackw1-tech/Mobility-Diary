import 'package:diary/mappers/auth_mapper.dart';
import 'package:diary/model/entities/auth/auth_session.dart';
import 'package:diary/model/entities/auth/auth_user.dart';
import 'package:diary/network/service/auth_service.dart';
import 'package:diary/network/service/auth_session_store.dart';
import 'package:diary/network/service/impl/auth_http_service.dart';
import 'package:diary/network/service/impl/secure_auth_session_store.dart';
import 'package:diary/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthService _service;
  final AuthMapper _mapper;
  final AuthSessionStore _sessionStore;

  AuthUser? _currentUser;
  String? _accessToken;

  AuthRepositoryImpl({
    AuthService? service,
    AuthMapper? mapper,
    AuthSessionStore? sessionStore,
  })  : _service = service ?? AuthHttpService(),
        _mapper = mapper ?? AuthMapper(),
        _sessionStore = sessionStore ?? const SecureAuthSessionStore();

  @override
  AuthUser? get currentUser => _currentUser;

  @override
  String? get accessToken => _accessToken;

  @override
  bool get isAuthenticated => _accessToken != null && _currentUser != null;

  @override
  Future<AuthSession?> restoreSession() async {
    final storedToken = await _sessionStore.readAccessToken();
    if (storedToken == null || storedToken.isEmpty) {
      return null;
    }

    _accessToken = storedToken;
    try {
      final user = await loadCurrentUser();
      final expiresAt = await _sessionStore.readExpiresAt() ??
          DateTime.now().add(const Duration(days: 30));

      return AuthSession(
        user: user,
        accessToken: storedToken,
        tokenType: 'Bearer',
        expiresAt: expiresAt,
      );
    } catch (_) {
      await _clearSession();
      return null;
    }
  }

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final dto = await _service.login(
      email: email,
      password: password,
    );
    final session = _mapper.mapSession(dto);
    await _persistSession(session);
    return session;
  }

  @override
  Future<AuthSession> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    final dto = await _service.register(
      email: email,
      password: password,
      firstName: firstName,
      lastName: lastName,
    );
    final session = _mapper.mapSession(dto);
    await _persistSession(session);
    return session;
  }

  @override
  Future<AuthUser> loadCurrentUser() async {
    final token = _accessToken;
    if (token == null || token.isEmpty) {
      throw const AuthApiException('Sessione non disponibile');
    }
    final dto = await _service.fetchCurrentUser(accessToken: token);
    final user = _mapper.mapUser(dto);
    _currentUser = user;
    await _sessionStore.saveUser(user);
    return user;
  }

  @override
  Future<void> logout() async {
    final token = _accessToken;
    if (token != null) {
      try {
        await _service.logout(accessToken: token);
      } catch (_) {
        // Local logout must still succeed if the server is unavailable.
      }
    }
    await _clearSession();
  }

  Future<void> _persistSession(AuthSession session) async {
    _accessToken = session.accessToken;
    _currentUser = session.user;
    await _sessionStore.saveSession(session);
  }

  Future<void> _clearSession() async {
    _accessToken = null;
    _currentUser = null;
    await _sessionStore.clear();
  }
}
