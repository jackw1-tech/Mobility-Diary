import 'package:diary/features/auth/domain/auth_session.dart';
import 'package:diary/features/auth/domain/auth_user.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:diary/main.dart';
import 'package:diary/repositories/auth_repository.dart';

void main() {
  testWidgets('Diary app mounts without framework errors', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      DiaryApp(authRepository: _AuthenticatedAuthRepository()),
    );
    // La home monta la mappa live (platform view Mapbox) e uno spinner mentre
    // risolve la posizione: pumpAndSettle non converge per via dell'animazione,
    // quindi si pompano qualche frame in modo deterministico.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.byType(DiaryApp), findsOneWidget);

    // Le metriche stanno nel bottom sheet trascinabile: vanno scrollate in vista
    // perché la ListView è lazy e parte collassata.
    await tester.scrollUntilVisible(
      find.text('Sigma'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Sigma'), findsOneWidget);
    expect(find.text('Sensori reali'), findsNothing);
  });
}

class _AuthenticatedAuthRepository implements AuthRepository {
  final AuthUser _user = const AuthUser(
    id: 1,
    email: 'test@example.com',
    firstName: 'Test',
    lastName: 'User',
    isStaff: false,
    isSuperuser: false,
  );

  @override
  String? get accessToken => 'test-token';

  @override
  AuthUser? get currentUser => _user;

  @override
  bool get isAuthenticated => true;

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    return _session;
  }

  @override
  Future<AuthSession> loginAsGuest() async => _session;

  @override
  Future<void> logout() async {}

  @override
  Future<AuthUser> loadCurrentUser() async => _user;

  @override
  Future<AuthSession> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    return _session;
  }

  @override
  Future<AuthSession?> restoreSession() async => _session;

  AuthSession get _session => AuthSession(
        user: _user,
        accessToken: 'test-token',
        tokenType: 'Bearer',
        expiresAt: DateTime.utc(2026, 7),
      );
}
