import 'package:auto_route/auto_route.dart';
import 'package:diary/repositories/auth_repository.dart';

class AuthGuard extends AutoRouteGuard {
  final AuthRepository _authRepository;

  const AuthGuard(this._authRepository);

  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) async {
    if (_authRepository.isAuthenticated) {
      resolver.next(true);
      return;
    }

    final session = await _authRepository.restoreSession();
    if (session != null) {
      resolver.next(true);
      return;
    }

    resolver.next(false);
    router.replacePath('/');
  }
}
